import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BookFileReader = Future<Uint8List?> Function(String bookId);
typedef PendingCoverReader = Future<Uint8List?> Function(MediaStorageScope scope, String bookId);
typedef MediaUploader = Future<MediaAsset> Function(MediaUploadPayload payload);
typedef MediaWorkAvailableCallback = Future<void> Function();

enum MediaUploadTaskStatus { pending, failed }

class MediaUploadTask {
  const MediaUploadTask({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.filename,
    required this.contentType,
    required this.status,
    this.coverBase64,
    this.errorMessage,
  });

  final String id;
  final String bookId;
  final MediaKind kind;
  final String filename;
  final String contentType;
  final MediaUploadTaskStatus status;
  final String? coverBase64;
  final String? errorMessage;

  MediaUploadTask copyWith({MediaUploadTaskStatus? status, String? errorMessage}) {
    return MediaUploadTask(
      id: id,
      bookId: bookId,
      kind: kind,
      filename: filename,
      contentType: contentType,
      status: status ?? this.status,
      coverBase64: coverBase64,
      errorMessage: errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'book_id': bookId,
      'kind': kind.apiValue,
      'filename': filename,
      'content_type': contentType,
      'status': status.name,
      if (coverBase64 != null) 'cover_base64': coverBase64,
      'error_message': errorMessage,
    };
  }

  factory MediaUploadTask.fromJson(Map<String, dynamic> json) {
    return MediaUploadTask(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      kind: MediaKind.fromApiValue(json['kind'] as String),
      filename: json['filename'] as String,
      contentType: json['content_type'] as String,
      status: MediaUploadTaskStatus.values.byName(json['status'] as String? ?? MediaUploadTaskStatus.pending.name),
      coverBase64: json['cover_base64'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class MediaUploadQueue extends ChangeNotifier {
  MediaUploadQueue(this._prefs, {this.onWorkAvailable});

  static const _storageKeyPrefix = 'media_upload_queue:';

  final SharedPreferences _prefs;
  final MediaWorkAvailableCallback? onWorkAvailable;
  List<MediaUploadTask> _tasks = [];
  MediaStorageScope? _activeScope;
  MediaStorageUsage? _storageUsage;
  Future<void>? _processing;
  bool _processAgain = false;
  Future<void> _mutationTail = Future<void>.value();
  Map<String, int> _taskVersions = {};

  List<MediaUploadTask> get pendingTasks => List.unmodifiable(_tasks);
  MediaStorageScope? get activeScope => _activeScope;
  MediaStorageUsage? get storageUsage => _storageUsage;

  Future<void> activateScope(MediaStorageScope? scope) async {
    if (_activeScope == scope) return;
    await waitUntilIdle();
    await _waitForMutations();
    _activeScope = scope;
    _tasks = scope == null ? [] : _loadTasks(scope);
    _taskVersions = {for (final task in _tasks) task.id: 0};
    _storageUsage = null;
    notifyListeners();
  }

  Future<void> waitUntilIdle() => _processing ?? Future<void>.value();

  Future<void> refreshUsage(Future<MediaStorageUsage> Function() fetchUsage) async {
    _storageUsage = await fetchUsage();
    notifyListeners();
  }

  Future<void> enqueueBookFile({required Book book, required String filename, required String contentType}) {
    return _enqueue(
      MediaUploadTask(
        id: '${book.id}:book_file',
        bookId: book.id,
        kind: MediaKind.bookFile,
        filename: filename,
        contentType: contentType,
        status: MediaUploadTaskStatus.pending,
      ),
    );
  }

  Future<void> enqueueCover({required Book book, required String filename, required String contentType}) {
    return _enqueue(
      MediaUploadTask(
        id: '${book.id}:cover_image',
        bookId: book.id,
        kind: MediaKind.coverImage,
        filename: filename,
        contentType: contentType,
        status: MediaUploadTaskStatus.pending,
      ),
    );
  }

  Future<void> enqueueImportedBookMedia({
    required MediaStorageScope scope,
    required Book book,
    required String filename,
    required String contentType,
    String? coverFilename,
    String? coverContentType,
  }) async {
    if ((coverFilename == null) != (coverContentType == null)) {
      throw ArgumentError('Cover filename and content type must be provided together');
    }

    final tasks = [
      MediaUploadTask(
        id: '${book.id}:book_file',
        bookId: book.id,
        kind: MediaKind.bookFile,
        filename: filename,
        contentType: contentType,
        status: MediaUploadTaskStatus.pending,
      ),
      if (coverFilename != null)
        MediaUploadTask(
          id: '${book.id}:cover_image',
          bookId: book.id,
          kind: MediaKind.coverImage,
          filename: coverFilename,
          contentType: coverContentType!,
          status: MediaUploadTaskStatus.pending,
        ),
    ];

    await _withMutation(() async {
      if (_activeScope != scope) {
        throw StateError('Authenticated media upload scope changed before import commit');
      }
      final taskIds = tasks.map((task) => task.id).toSet();
      final nextTasks = [..._tasks.where((task) => !taskIds.contains(task.id)), ...tasks];
      await _saveTasks(scope, nextTasks);
      for (final task in tasks) {
        _advanceTaskVersion(task.id);
      }
      _tasks = nextTasks;
      notifyListeners();
    });
    await _notifyWorkAvailableBestEffort();
  }

  Future<void> retryFailed({String? bookId}) async {
    final scope = _requireActiveScope();
    var retriedAny = false;
    await _withMutation(() async {
      _tasks = _tasks
          .map((task) {
            final matchesBook = bookId == null || task.bookId == bookId;
            if (!matchesBook || task.status != MediaUploadTaskStatus.failed) {
              return task;
            }
            retriedAny = true;
            _advanceTaskVersion(task.id);
            return task.copyWith(status: MediaUploadTaskStatus.pending);
          })
          .toList(growable: false);
      await _save(scope);
      notifyListeners();
    });
    if (retriedAny) {
      await onWorkAvailable?.call();
    }
  }

  Future<void> removeTasksForBook(String bookId) async {
    final scope = _activeScope;
    if (scope == null) return;
    await _withMutation(() async {
      for (final task in _tasks.where((task) => task.bookId == bookId)) {
        _advanceTaskVersion(task.id);
      }
      _tasks = _tasks.where((task) => task.bookId != bookId).toList(growable: false);
      await _save(scope);
      notifyListeners();
    });
  }

  Future<void> processPending({
    required DataStore dataStore,
    required BookFileReader readBookFile,
    required PendingCoverReader readPendingCover,
    required MediaUploader uploadMedia,
  }) {
    final inFlight = _processing;
    if (inFlight != null) {
      _processAgain = true;
      return inFlight;
    }
    final scope = _activeScope;
    if (scope == null) return Future<void>.value();

    final completer = Completer<void>();
    final operation = completer.future;
    _processing = operation;
    unawaited(() async {
      try {
        do {
          _processAgain = false;
          await _processPending(
            scope: scope,
            dataStore: dataStore,
            readBookFile: readBookFile,
            readPendingCover: readPendingCover,
            uploadMedia: uploadMedia,
          );
        } while (_processAgain && _activeScope == scope);
        _clearProcessing(operation);
        completer.complete();
      } catch (error, stackTrace) {
        _clearProcessing(operation);
        completer.completeError(error, stackTrace);
      }
    }());
    return operation;
  }

  Future<void> _processPending({
    required MediaStorageScope scope,
    required DataStore dataStore,
    required BookFileReader readBookFile,
    required PendingCoverReader readPendingCover,
    required MediaUploader uploadMedia,
  }) async {
    final processedVersions = <String>{};
    while (_activeScope == scope) {
      await _waitForMutations();
      final tasks = _tasks
          .where((task) {
            if (task.status == MediaUploadTaskStatus.failed) return false;
            return !processedVersions.contains(_taskVersionKey(task.id));
          })
          .toList(growable: false);
      if (tasks.isEmpty) return;

      for (final task in tasks) {
        final version = _taskVersions[task.id] ?? 0;
        processedVersions.add('${task.id}:$version');

        try {
          final bytes = await _bytesForTask(task, scope, readBookFile, readPendingCover);
          if (bytes == null) {
            await _replaceTaskIfCurrent(
              scope,
              task,
              version,
              task.copyWith(status: MediaUploadTaskStatus.pending, errorMessage: 'Local file not found'),
            );
            continue;
          }

          await uploadMedia(
            MediaUploadPayload(
              bookId: task.bookId,
              kind: task.kind,
              filename: task.filename,
              contentType: task.contentType,
              bytes: bytes,
            ),
          );
          await _removeTaskIfCurrent(scope, task, version);
        } on MediaUploadException catch (error) {
          await _replaceTaskIfCurrent(
            scope,
            task,
            version,
            task.copyWith(
              status: error.storageFull ? MediaUploadTaskStatus.failed : MediaUploadTaskStatus.pending,
              errorMessage: error.message,
            ),
          );
        } catch (error) {
          await _replaceTaskIfCurrent(
            scope,
            task,
            version,
            task.copyWith(status: MediaUploadTaskStatus.pending, errorMessage: error.toString()),
          );
        }
      }
    }
  }

  Future<void> _enqueue(MediaUploadTask task) async {
    final scope = _requireActiveScope();
    await _withMutation(() async {
      _advanceTaskVersion(task.id);
      _tasks = [..._tasks.where((existing) => existing.id != task.id), task];
      await _save(scope);
      notifyListeners();
    });
    await onWorkAvailable?.call();
  }

  Future<void> _notifyWorkAvailableBestEffort() async {
    try {
      await onWorkAvailable?.call();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'papyrus media upload queue',
          context: ErrorDescription('while notifying work for a committed import batch'),
        ),
      );
    }
  }

  Future<void> _removeTaskIfCurrent(MediaStorageScope scope, MediaUploadTask task, int version) {
    return _withMutation(() async {
      final index = _currentTaskIndex(task, version);
      if (index < 0) return;
      _tasks = [..._tasks]..removeAt(index);
      await _save(scope);
      notifyListeners();
    });
  }

  Future<void> _replaceTaskIfCurrent(
    MediaStorageScope scope,
    MediaUploadTask task,
    int version,
    MediaUploadTask replacement,
  ) {
    return _withMutation(() async {
      final index = _currentTaskIndex(task, version);
      if (index < 0) return;
      _tasks = [..._tasks]..[index] = replacement;
      await _save(scope);
      notifyListeners();
    });
  }

  int _currentTaskIndex(MediaUploadTask task, int version) {
    if ((_taskVersions[task.id] ?? 0) != version) return -1;
    return _tasks.indexWhere((candidate) => identical(candidate, task));
  }

  String _taskVersionKey(String taskId) => '$taskId:${_taskVersions[taskId] ?? 0}';

  void _advanceTaskVersion(String taskId) {
    _taskVersions[taskId] = (_taskVersions[taskId] ?? 0) + 1;
  }

  Future<T> _withMutation<T>(FutureOr<T> Function() mutation) {
    final previous = _mutationTail;
    final released = Completer<void>();
    _mutationTail = released.future;
    return (() async {
      await previous;
      try {
        return await mutation();
      } finally {
        released.complete();
      }
    })();
  }

  Future<void> _waitForMutations() async {
    while (true) {
      final pending = _mutationTail;
      await pending;
      if (identical(pending, _mutationTail)) return;
    }
  }

  Future<Uint8List?> _bytesForTask(
    MediaUploadTask task,
    MediaStorageScope scope,
    BookFileReader readBookFile,
    PendingCoverReader readPendingCover,
  ) async {
    if (task.kind == MediaKind.coverImage) {
      final coverBase64 = task.coverBase64;
      if (coverBase64 != null) return base64Decode(coverBase64);
      return readPendingCover(scope, task.bookId);
    }
    return readBookFile(task.bookId);
  }

  List<MediaUploadTask> _loadTasks(MediaStorageScope scope) {
    final raw = _prefs.getString(_storageKey(scope));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => MediaUploadTask.fromJson(item as Map<String, dynamic>)).toList(growable: false);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'papyrus media upload queue',
          context: ErrorDescription('while loading persisted media uploads'),
        ),
      );
      return [];
    }
  }

  Future<void> _save(MediaStorageScope scope) => _saveTasks(scope, _tasks);

  Future<void> _saveTasks(MediaStorageScope scope, List<MediaUploadTask> tasks) async {
    final saved = await _prefs.setString(_storageKey(scope), jsonEncode(tasks.map((task) => task.toJson()).toList()));
    if (!saved) {
      throw StateError('Could not persist media upload queue');
    }
  }

  String _storageKey(MediaStorageScope scope) => '$_storageKeyPrefix${scope.persistenceKey}';

  MediaStorageScope _requireActiveScope() {
    final scope = _activeScope;
    if (scope == null) {
      throw StateError('Authenticated media upload scope is not active');
    }
    return scope;
  }

  void _clearProcessing(Future<void> operation) {
    if (identical(_processing, operation)) {
      _processing = null;
    }
  }
}
