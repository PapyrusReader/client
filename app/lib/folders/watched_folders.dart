import 'dart:async';

import 'package:papyrus/folders/folder_fingerprint.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_import_target.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/folder_repository.dart';
import 'package:papyrus/widgets/add_book/book_import_controller.dart';
import 'package:uuid/uuid.dart';

class _ScanCancelled implements Exception {}

enum _FileResult { processed, deferred }

class _FolderWork {
  _FolderWork(this.recordId, {this.job});

  final String recordId;
  final Map<String, dynamic>? job;
  FolderFile? file;
}

/// Owns scheduling and durable work independently of the Library page lifetime.
class WatchedFolders extends ChangeNotifier with WidgetsBindingObserver {
  WatchedFolders({
    required this.access,
    required this.captureTarget,
    required this.libraryReady,
    this.deleteStagedFile,
    Future<FolderRepository> Function(String)? openRepository,
    DateTime Function()? now,
    this.stabilityDelay = const Duration(seconds: 2),
    this.pollInterval = const Duration(seconds: 60),
  }) : _openRepository = openRepository ?? FolderRepository.open,
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final DirectoryAccess access;
  final FolderImportTarget Function() captureTarget;
  final bool Function() libraryReady;
  final Future<void> Function(String)? deleteStagedFile;
  final Future<FolderRepository> Function(String) _openRepository;
  final DateTime Function() _now;
  final Duration stabilityDelay;
  final Duration pollInterval;
  final String _owner = const Uuid().v4();
  FolderRepository? _repository;
  final List<WatchedFolder> _folders = [];
  final Map<String, Set<String>> _bookIds = {};
  final Map<String, String> _knownHashes = {};
  final Map<String, String> _pendingHashes = {};

  Set<String> bookIds(String folderId) => _bookIds[folderId] ?? const {};
  final Map<String, StreamSubscription<void>> _events = {};
  final Map<String, Timer> _debounces = {};
  final Set<String> _requested = {};
  Future<void>? _running;
  Future<void> _edits = Future.value();
  int _pendingEdits = 0;
  bool _scanAll = false;
  Future<void> _scopeChange = Future.value();
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _suspended = false;
  bool _hasLease = false;
  DateTime? _leaseExpires;
  Timer? _heartbeat;
  Future<void>? _renewing;
  bool get _leaseValid => _hasLease && _leaseExpires != null && _now().isBefore(_leaseExpires!);
  String? _scope;
  String? error;

  List<WatchedFolder> get folders => List.unmodifiable(_folders);
  bool get ready => _repository != null && libraryReady() && !_suspended;
  String? get scope => _scope;
  bool get supportsWatching => access.supportsWatching;
  bool get _desktop =>
      !kIsWeb &&
      const [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform);
  List<String> get extensions => kIsWeb ? bookImportWebExtensions : bookImportNativeExtensions;
  bool _supported(FolderFile file) => extensions.contains(file.name.split('.').last.toLowerCase());

  Future<void> activate(String? scope) {
    if (_disposed) {
      return Future.value();
    }

    if (_scope == scope && (_repository != null || scope == null)) {
      return _scopeChange;
    }

    _timer?.cancel();
    _timer = scope == null ? null : Timer.periodic(pollInterval, (_) => schedule());
    _scope = scope;
    _generation++;
    _requested.clear();
    final generation = _generation;
    _scopeChange = _scopeChange.catchError((Object _) {}).then((_) async {
      await _running;
      await _edits.catchError((Object _) {});
      await _cancelEvents();
      await _repository?.close();
      _repository = null;
      _folders.clear();
      _bookIds.clear();

      if (generation != _generation || _disposed) {
        return;
      }

      if (scope != null) {
        try {
          final repository = await _openRepository(scope);

          if (generation != _generation || _disposed) {
            await repository.close();
            return;
          }

          _repository = repository;
          _suspended = false;
          _folders.addAll(await repository.folders());

          _bookIds.addAll(await repository.bookIds());
          error = null;
          _listen();
        } catch (failure) {
          error = 'Could not open watched folders: $failure';
        }
      }

      _notify();
      schedule();
    });
    return _scopeChange;
  }

  void invalidate() {
    _generation++;
    _requested.clear();
  }

  Future<void> suspend() async {
    _suspended = true;
    invalidate();
    await _running;
    await _edits.catchError((Object _) {});
  }

  void resume() {
    _suspended = false;
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_desktop) {
      return;
    }

    _foreground = state == AppLifecycleState.resumed;

    if (_foreground) {
      schedule();
    } else {
      invalidate();
    }
  }

  void schedule([String? folderId]) {
    if (_disposed || !ready || !_foreground || _pendingEdits > 0) {
      return;
    }

    _scanAll = _scanAll || folderId == null;
    _requested.addAll(
      folderId == null ? _folders.where((folder) => folder.enabled).map((folder) => folder.id) : [folderId],
    );

    if (_running != null || (_requested.isEmpty && !_scanAll)) {
      return;
    }

    _running = _drain()
        .catchError((Object failure, StackTrace stack) {
          if (failure is! _ScanCancelled) {
            error = 'Folder scan could not finish: $failure';
          }
        })
        .whenComplete(() {
          _running = null;
          _notify();
        });
  }

  Future<void> scanNow(String id) async {
    schedule(id);
    await _running;
  }

  Future<void> waitUntilIdle() async => _running;

  Future<void> _drain() async {
    final repository = _repository!;
    final generation = _generation;

    if (!await _acquireLease(repository)) {
      _requested.clear();
      error = 'Another Papyrus window is checking these folders.';
      return;
    }

    try {
      await _releaseRetiredGrants(repository);
      await _refreshFolders(repository);

      if (_scanAll) {
        _requested.addAll(_folders.where((folder) => folder.enabled).map((folder) => folder.id));
        _scanAll = false;
      }

      while (_requested.isNotEmpty && generation == _generation && !_disposed && ready && _foreground) {
        final id = _requested.first;
        _requested.remove(id);
        final folder = _folders.where((folder) => folder.id == id).firstOrNull;

        if (folder != null && folder.enabled) {
          await _scan(repository, folder, generation);
        }
      }
    } finally {
      await _releaseLease(repository);
    }
  }

  Future<bool> _acquireLease(FolderRepository repository) async {
    final started = _now();

    if (!await repository.acquire(_owner, started)) {
      return false;
    }

    _hasLease = true;
    _leaseExpires = started.add(FolderRepository.leaseDuration);
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_renewing != null) {
        return;
      }

      _renewing = (() async {
        try {
          final started = _now();
          _hasLease = await repository.acquire(_owner, started);
          _leaseExpires = started.add(FolderRepository.leaseDuration);
        } catch (_) {
          _hasLease = false;
        }
      })().whenComplete(() => _renewing = null);
    });
    return true;
  }

  Future<void> _releaseLease(FolderRepository repository) async {
    _heartbeat?.cancel();
    await _renewing;
    _hasLease = false;
    await repository.release(_owner);
  }

  void _checkEditLease() {
    if (!_leaseValid) {
      throw StateError('Folder access changed in another window. Try again.');
    }
  }

  Future<void> _refreshFolders(FolderRepository repository) async {
    final saved = await repository.folders();
    final identities = saved.map((folder) => folder.id).toSet();

    for (final current in _folders.toList()) {
      final restored = saved.where((folder) => folder.id == current.id).firstOrNull;

      if (restored == null || restored.grant.key != current.grant.key) {
        await _events.remove(current.id)?.cancel();
      }

      if (restored != null) {
        current.restore(restored);
      }
    }

    _folders.removeWhere((folder) => !identities.contains(folder.id));

    for (final folder in saved) {
      if (!_folders.any((current) => current.id == folder.id)) {
        _folders.add(folder);
      }
    }

    _bookIds.clear();
    _bookIds.addAll(await repository.bookIds());

    _listen();
  }

  Future<void> _releaseRetiredGrants(FolderRepository repository) async {
    for (final grant in await repository.retiredGrants()) {
      try {
        await access.release(grant);
        await repository.forgetGrant(grant.key);
      } catch (_) {
        // A committed replacement must not lose its new grant when cleanup fails.
        // The old grant remains journaled for another scan or restart.
      }
    }
  }

  Future<void> _edit(Future<void> Function(FolderRepository) action) {
    final repository = _repository;
    final scope = _scope;
    invalidate();
    _pendingEdits++;
    final operation = _edits.catchError((Object _) {}).then((_) async {
      await _running;

      if (repository == null || repository != _repository || scope != _scope || _disposed) {
        throw StateError('The selected library changed.');
      }

      if (!await _acquireLease(repository)) {
        throw StateError('Another Papyrus window is checking these folders. Try again when it finishes.');
      }

      try {
        await _refreshFolders(repository);
        _checkEditLease();
        await action(repository);
      } finally {
        await _releaseLease(repository);
      }
    });

    _edits = operation.whenComplete(() {
      _pendingEdits--;
      _notify();
      schedule();
    });
    return _edits;
  }

  void _check(FolderImportTarget target, WatchedFolder folder, int generation) {
    if (_disposed ||
        !_leaseValid ||
        generation != _generation ||
        !target.isCurrent ||
        !folder.enabled ||
        !_foreground ||
        _suspended) {
      throw _ScanCancelled();
    }
  }

  Future<FolderPreview> preview(FolderGrant grant, bool recursive, {bool Function()? cancelled}) async {
    final result = FolderPreview();

    await for (final file in access.enumerate(grant, recursive: recursive)) {
      if (_disposed || cancelled?.call() == true) {
        break;
      }

      if (file.error != null) {
        result.inaccessible++;
      } else if (_supported(file)) {
        result.supported++;

        if (file.size < 0) {
          result.unknownSizes++;
        } else {
          result.bytes += file.size;
        }
      } else {
        result.unsupported++;
      }
    }

    return result;
  }

  Future<void> connect(FolderGrant grant, {String? name, bool recursive = true, String? shelfId}) async {
    if (!ready) {
      throw StateError('Wait for the selected library to finish loading.');
    }

    await _edit((repository) async {
      if (_folders.any((folder) => folder.grant.identity == grant.identity)) {
        throw StateError('This folder is already connected to this library.');
      }

      final folder = WatchedFolder(
        id: const Uuid().v4(),
        grant: grant,
        customName: _folderName(name ?? grant.name),
        recursive: recursive,
        shelfId: shelfId,
      );
      await repository.saveFolder(folder);
      _folders.add(folder);
      _listen();
    });
  }

  Future<void> update(
    WatchedFolder folder, {
    String? name,
    bool? enabled,
    bool? recursive,
    String? shelfId,
    bool changeShelf = false,
  }) => _edit((repository) async {
    _requireFolder(folder);
    final updated = WatchedFolder.fromJson(folder.toJson());

    if (name != null) {
      updated.customName = _folderName(name);
    }

    if (enabled != null) {
      updated.enabled = enabled;
      updated.status = enabled ? FolderStatus.upToDate : FolderStatus.paused;
    }

    if (changeShelf) {
      updated.shelfId = shelfId;
    }

    if (recursive != null) {
      updated.recursive = recursive;
    }

    await repository.saveFolder(updated);
    folder.restore(updated);
  });

  String _folderName(String value) {
    final name = value.trim();

    if (name.isEmpty) {
      throw ArgumentError('Enter a folder name.');
    }

    return name;
  }

  void _requireFolder(WatchedFolder folder) {
    if (!_folders.contains(folder)) {
      throw StateError('This folder connection was removed in another window.');
    }
  }

  Future<void> reconnect(WatchedFolder folder) async {
    if (!await access.reconnect(folder.grant)) {
      throw const FolderAccessException('access', 'Access was not restored. Select the folder again.');
    }

    await _events.remove(folder.id)?.cancel();
    await update(folder, enabled: true);
    _listen();
  }

  Future<void> replaceGrant(WatchedFolder folder, FolderGrant grant) => _edit((repository) async {
    _requireFolder(folder);
    if (_folders.any((other) => other.id != folder.id && other.grant.identity == grant.identity)) {
      throw StateError('This folder is already connected to this library.');
    }

    await _events.remove(folder.id)?.cancel();
    final old = folder.grant;
    final updated = WatchedFolder.fromJson(folder.toJson());
    updated.grant = grant;
    updated.enabled = true;
    _checkEditLease();
    await repository.replaceGrant(updated, old);
    folder.restore(updated);
    await _releaseRetiredGrants(repository);
    _listen();
  });

  Future<void> stop(WatchedFolder folder) => _edit((repository) async {
    _requireFolder(folder);
    final target = captureTarget();

    for (final job in await repository.records('jobs', folderId: folder.id)) {
      final bookId = job['bookId'] as String;

      if (await target.getBook(bookId) == null) {
        await target.deleteStaged(bookId);
      }
    }

    _checkEditLease();
    await repository.removeFolder(folder.id);
    _folders.remove(folder);
    _bookIds.remove(folder.id);
    await _events.remove(folder.id)?.cancel();
    await _releaseRetiredGrants(repository);
    _notify();
  });

  Future<List<Map<String, dynamic>>> issues(String id) async => [
    for (final record in await _repository!.records('files', folderId: id))
      if (const ['changed', 'failed', 'excluded'].contains(record['state'])) record,
    for (final job in await _repository!.records('jobs', folderId: id))
      if (job['detached'] == true && job['state'] == 'failed') job,
  ];

  Future<void> review(WatchedFolder folder, Map<String, dynamic> record, {required bool import}) =>
      _edit((repository) async {
        _requireFolder(folder);
        final id = record['recordId'] as String;
        final next = Map<String, dynamic>.from(record)..remove('recordId');

        if (import) {
          final hash = record['hash'] as String?;

          if (hash != null) {
            await repository.allow(hash);
          }

          next['state'] = 'requested';
        } else {
          next['state'] = 'ignored';
        }

        await repository.save('files', id, next, folderId: folder.id);
      });

  Future<void> retry(WatchedFolder folder) => _edit((repository) async {
    _requireFolder(folder);
    final target = captureTarget();

    for (final job in await _repository!.records('jobs', folderId: folder.id)) {
      final bookId = job['bookId'] as String;
      final bytes = await target.readStored(bookId);

      if (bytes != null && await fingerprint(bytes) != job['hash'] && await target.getBook(bookId) == null) {
        await target.deleteStaged(bookId);
      }

      job['state'] = 'pending';
      job.remove('error');
      await _repository!.save('jobs', job['recordId'] as String, job, folderId: folder.id);
    }

    for (final file in await _repository!.records('files', folderId: folder.id)) {
      if (file['state'] == 'failed') {
        file['state'] = 'retry';
        await _repository!.save('files', file['recordId'] as String, file, folderId: folder.id);
      }
    }
  });

  Future<void> recordDeletion(String bookId, String? hash) async {
    final repository = _repository;

    if (repository == null) {
      return;
    }

    if (hash != null) {
      await _edit((repository) async {
        await repository.exclude(hash, bookId);

        for (final job in await repository.records('jobs')) {
          if (job['bookId'] == bookId) {
            await repository.delete('jobs', job['recordId'] as String);
          }
        }
      });
    }
  }

  Future<void> clear() async {
    await suspend();
    await _cancelEvents();

    if (deleteStagedFile != null && _repository != null) {
      for (final job in await _repository!.records('jobs')) {
        await deleteStagedFile!(job['bookId'] as String);
      }
    }

    for (final folder in _folders) {
      await access.release(folder.grant);
    }

    if (_repository != null) {
      await _releaseRetiredGrants(_repository!);
    }

    await _repository?.clear();
    _folders.clear();
    _bookIds.clear();
    _notify();
  }

  Future<void> _scan(FolderRepository repository, WatchedFolder folder, int generation) async {
    final target = captureTarget();
    folder.status = FolderStatus.scanning;
    folder.progress = null;
    folder.error = null;
    folder.unsupported = 0;
    error = null;
    _notify();

    try {
      _knownHashes.clear();
      _pendingHashes.clear();

      for (final record in await repository.records('files')) {
        if (record['state'] == 'done' && record['hash'] != null && record['bookId'] != null) {
          _knownHashes[record['hash'] as String] = record['bookId'] as String;
        }
      }

      for (final job in await repository.records('jobs')) {
        if (job['hash'] != null && job['bookId'] != null) {
          _knownHashes[job['hash'] as String] = job['bookId'] as String;
          _pendingHashes[job['hash'] as String] = job['bookId'] as String;
        }
      }

      for (final book in target.books) {
        if (book.fileHash != null) {
          _knownHashes[book.fileHash!] = book.id;
        }
      }

      final work = <String, _FolderWork>{};

      for (final job in await repository.records('jobs', folderId: folder.id)) {
        if (job['state'] != 'failed') {
          final id = job['recordId'] as String;
          work[id] = _FolderWork(id, job: job);
        }
      }

      Object? enumerationFailure;

      try {
        await for (final file in access.enumerate(folder.grant, recursive: folder.recursive)) {
          _check(target, folder, generation);

          if (file.error == null && !_supported(file)) {
            folder.unsupported++;
            continue;
          }

          final recordId = '${folder.id}:${file.key}';
          final previous = await repository.get('files', recordId);

          if (_unchanged(file, previous) && !work.containsKey(recordId)) {
            // Reconcile library deletions without counting unchanged files as imports.
            await _consider(repository, folder, target, generation, file, recordId, previous);
            continue;
          }

          (work[recordId] ??= _FolderWork(recordId)).file = file;
        }
      } on _ScanCancelled {
        rethrow;
      } catch (failure) {
        // Staged jobs can still recover when the source folder is unavailable.
        enumerationFailure = failure;
      }

      _check(target, folder, generation);
      final progress = FolderImportProgress(total: work.length);

      if (work.isNotEmpty) {
        folder.progress = progress;
        folder.status = FolderStatus.importing;
        _notify();
      }

      var hasDeferredFiles = false;

      for (final item in work.values) {
        _check(target, folder, generation);

        if (item.job != null) {
          await _recover(repository, folder, target, generation, item.job!);
        }

        final file = item.file;

        if (file != null) {
          final previous = await repository.get('files', item.recordId);

          try {
            final result = await _consider(repository, folder, target, generation, file, item.recordId, previous);

            if (result == _FileResult.deferred) {
              hasDeferredFiles = true;
            }
          } on _ScanCancelled {
            rethrow;
          } catch (failure) {
            await repository.save('files', item.recordId, {
              ...?previous,
              'key': file.key,
              'name': file.name,
              'stamp': file.stamp,
              'state': 'failed',
              'error': '$failure',
            }, folderId: folder.id);

            if (_outOfSpace(failure)) {
              rethrow;
            }
          }
        }

        _check(target, folder, generation);
        progress.processed++;
        _notify();
      }

      if (enumerationFailure != null) {
        throw enumerationFailure;
      }

      _check(target, folder, generation);
      final pendingIssues = await issues(folder.id);
      folder.status = pendingIssues.any((issue) => issue['state'] != 'excluded')
          ? FolderStatus.attention
          : FolderStatus.upToDate;
      folder.lastScan = DateTime.now();
      if (!folder.grant.persistent && !hasDeferredFiles) {
        folder.enabled = false;
        folder.status = FolderStatus.paused;
        folder.error = 'Select this folder again to import later additions.';
      }
    } on _ScanCancelled {
      folder.status = folder.enabled ? FolderStatus.upToDate : FolderStatus.paused;
    } on FolderAccessException catch (failure) {
      folder.status = failure.code == 'access' ? FolderStatus.accessNeeded : FolderStatus.unavailable;
      folder.error = failure.message;
    } catch (failure) {
      folder.status = FolderStatus.attention;
      folder.error = '$failure';
    } finally {
      folder.progress = null;

      if (_leaseValid) {
        await repository.saveFolder(folder);
      }

      _notify();
    }
  }

  Future<_FileResult> _consider(
    FolderRepository repository,
    WatchedFolder folder,
    FolderImportTarget target,
    int generation,
    FolderFile file,
    String recordId,
    Map<String, dynamic>? previous,
  ) async {
    _check(target, folder, generation);

    if (file.error != null) {
      throw FolderAccessException('unavailable', file.error!);
    }

    final previousId = previous?['bookId'] as String?;
    final previousHash = previous?['hash'] as String?;
    final requested = previous?['state'] == 'requested';

    final previouslyCommitted =
        const ['done', 'changed', 'ignored', 'excluded'].contains(previous?['state']) ||
        (previousId != null && await target.getBook(previousId) != null);

    if (!requested &&
        previouslyCommitted &&
        previousId != null &&
        previousHash != null &&
        await target.getBook(previousId) == null) {
      await repository.exclude(previousHash, previousId);
      await repository.save('files', recordId, {...previous!, 'state': 'excluded'}, folderId: folder.id);

      if (previous['stamp'] == file.stamp) {
        return _FileResult.processed;
      }
    }

    if (_unchanged(file, previous)) {
      return _FileResult.processed;
    }

    final now = _now().millisecondsSinceEpoch;

    if (file.modified > 0 && file.modified <= now && now - file.modified < stabilityDelay.inMilliseconds) {
      return _FileResult.deferred;
    }

    final needsObservation = file.modified == 0 || file.modified > now;

    if (needsObservation && (previous?['observedStamp'] != file.stamp || previous?['seen'] == null)) {
      await repository.save('files', recordId, {
        ...?previous,
        'observedStamp': file.stamp,
        'seen': now,
      }, folderId: folder.id);

      return _FileResult.deferred;
    }

    if (needsObservation && now - (previous!['seen'] as int) < stabilityDelay.inMilliseconds) {
      return _FileResult.deferred;
    }

    final start = await access.stat(folder.grant, file);
    final bytes = await access.read(folder.grant, file);
    final end = await access.stat(folder.grant, file);
    _check(target, folder, generation);

    if (start.stamp != end.stamp || (end.size >= 0 && bytes.length != end.size)) {
      return _FileResult.deferred;
    }

    final hash = await fingerprint(bytes);
    _check(target, folder, generation);

    final record = <String, dynamic>{
      'key': file.key,
      'name': file.name,
      'stamp': end.stamp,
      'hash': hash,
      'seen': now,
    };

    if (await repository.isExcluded(hash)) {
      await repository.save('files', recordId, {
        ...record,
        'state': 'excluded',
        'bookId': previousId,
      }, folderId: folder.id);
      return _FileResult.processed;
    }

    if (!requested && previousHash == hash && const ['done', 'ignored', 'changed'].contains(previous?['state'])) {
      await repository.save('files', recordId, {...previous!, ...record}, folderId: folder.id);
      return _FileResult.processed;
    }

    if (!requested && previouslyCommitted && previousId != null && previousHash != null && previousHash != hash) {
      await repository.save('files', recordId, {
        ...record,
        'state': 'changed',
        'bookId': previousId,
        'previousHash': previousHash,
      }, folderId: folder.id);
      return _FileResult.processed;
    }

    final knownId = _knownHashes[hash];
    final existing = knownId == null ? null : await target.getBook(knownId);

    if (existing != null) {
      _check(target, folder, generation);
      await target.ensureCopy(existing, bytes, file.name.split('.').last.toLowerCase(), folder.shelfId);
      await repository.save('files', recordId, {
        ...record,
        'state': 'done',
        'bookId': existing.id,
      }, folderId: folder.id);
      (_bookIds[folder.id] ??= {}).add(existing.id);
      folder.duplicates++;
      return _FileResult.processed;
    }

    final jobId = recordId;
    final saved = await repository.get('jobs', jobId);

    if (saved != null && saved['hash'] != hash) {
      // A source can change while an earlier import is waiting for its outbox.
      // Keep that recovery evidence without reusing or overwriting its book.
      final retainedId = '$jobId:retained:${saved['bookId']}';
      await repository.save('jobs', retainedId, {
        ...saved,
        'recordId': retainedId,
        'detached': true,
      }, folderId: folder.id);
    }

    final job = <String, dynamic>{
      ...record,
      'recordId': jobId,
      'bookId': saved?['hash'] == hash ? saved!['bookId'] : _pendingHashes[hash] ?? const Uuid().v4(),
      'state': 'pending',
    };
    await repository.save('jobs', jobId, job, folderId: folder.id);
    _knownHashes[hash] = job['bookId'] as String;
    _pendingHashes[hash] = job['bookId'] as String;
    await _recover(repository, folder, target, generation, job, bytes: bytes);
    return _FileResult.processed;
  }

  Future<void> _recover(
    FolderRepository repository,
    WatchedFolder folder,
    FolderImportTarget target,
    int generation,
    Map<String, dynamic> job, {
    Uint8List? bytes,
  }) async {
    final id = job['recordId'] as String;
    final bookId = job['bookId'] as String;
    _check(target, folder, generation);

    try {
      bytes ??= await target.readStored(bookId);

      if (bytes == null) {
        return;
      }

      if (await fingerprint(bytes) != job['hash']) {
        throw StateError('The staged file is incomplete. Retry this file from its source.');
      }

      if (await repository.isExcluded(job['hash'] as String)) {
        if (await target.getBook(bookId) == null) {
          await target.deleteStaged(bookId);
        }

        await repository.delete('jobs', id);
        return;
      }

      _check(target, folder, generation);
      final result = await target.process(bytes, job['name'] as String, bookId);
      _check(target, folder, generation);
      job['state'] = 'prepared';
      await repository.save('jobs', id, job, folderId: folder.id);
      _check(target, folder, generation);
      await target.finish(result, job['name'] as String, folder.shelfId);
      _check(target, folder, generation);
      if (job['detached'] != true) {
        await repository.save('files', id, {...job, 'state': 'done'}, folderId: folder.id);
      }

      await repository.delete('jobs', id);
      (_bookIds[folder.id] ??= {}).add(bookId);
      _knownHashes[job['hash'] as String] = bookId;
      folder.added++;
    } on _ScanCancelled {
      rethrow;
    } catch (failure) {
      job['state'] = 'failed';
      job['error'] = '$failure';
      await repository.save('jobs', id, job, folderId: folder.id);
      if (job['detached'] != true) {
        await repository.save('files', id, job, folderId: folder.id);
      }

      if (_outOfSpace(failure)) {
        throw StateError('Not enough local storage. Free up space, then retry failed imports.');
      }
    }
  }

  bool _unchanged(FolderFile file, Map<String, dynamic>? previous) =>
      file.error == null &&
      file.modified > 0 &&
      previous?['stamp'] == file.stamp &&
      const ['done', 'ignored', 'changed', 'failed', 'excluded'].contains(previous?['state']);

  bool _outOfSpace(Object failure) => RegExp(
    r'no space|disk full|quotaexceeded|not enough (local )?storage|ENOSPC',
    caseSensitive: false,
  ).hasMatch('$failure');

  void _listen() {
    for (final folder in _folders) {
      if (_events.containsKey(folder.id) || !folder.grant.persistent) {
        continue;
      }

      _events[folder.id] = access
          .changes(folder.grant)
          .listen(
            (_) {
              _debounces.remove(folder.id)?.cancel();
              _debounces[folder.id] = Timer(stabilityDelay, () => schedule(folder.id));
            },
            onError: (Object _) {
              // Periodic reconciliation continues when OS event delivery is unavailable.
            },
          );
    }
  }

  Future<void> _cancelEvents() async {
    for (final timer in _debounces.values) {
      timer.cancel();
    }

    _debounces.clear();

    for (final subscription in _events.values) {
      await subscription.cancel();
    }

    _events.clear();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _scopeChange;
    await _running;
    await _edits.catchError((Object _) {});
    await _cancelEvents();
    await _repository?.close();
    _repository = null;
  }
}
