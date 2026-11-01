import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_import_target.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/folder_repository.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_result.dart';

const grant = FolderGrant(key: 'root', identity: 'root', name: 'Books', location: '/Books');

class MemoryAccess implements DirectoryAccess {
  FolderGrant selected = grant;
  final files = <String, Uint8List>{};
  final revisions = <String, int>{};
  int reads = 0;
  int enumerated = 0;
  String? failure;
  int? reportedSize;
  int? reportedModified;
  bool failRelease = false;
  final released = <String>[];
  void Function()? afterRead;
  void Function()? afterEnumerate;

  void put(String name, List<int> bytes) {
    files[name] = Uint8List.fromList(bytes);
    revisions[name] = (revisions[name] ?? 100) + 1;
  }

  @override
  bool get supportsWatching => true;

  @override
  Future<FolderGrant?> pick() async => selected;

  @override
  Future<bool> reconnect(FolderGrant grant) async => failure == null;

  FolderFile info(String name) => FolderFile(
    key: name,
    name: name.split('/').last,
    size: reportedSize ?? files[name]!.length,
    modified: reportedModified ?? revisions[name] ?? 1,
  );

  @override
  Stream<FolderFile> enumerate(FolderGrant grant, {required bool recursive}) async* {
    if (failure != null) {
      throw FolderAccessException(failure!, 'Folder cannot be accessed.');
    }

    for (final name in files.keys.toList()) {
      if (recursive || !name.contains('/')) {
        enumerated++;
        afterEnumerate?.call();
        yield info(name);
      }
    }
  }

  @override
  Future<FolderFile> stat(FolderGrant grant, FolderFile file) async => info(file.key);

  @override
  Future<Uint8List> read(FolderGrant grant, FolderFile file) async {
    reads++;
    final bytes = Uint8List.fromList(files[file.key]!);
    afterRead?.call();
    return bytes;
  }

  @override
  Stream<void> changes(FolderGrant grant) => const Stream.empty();

  @override
  Future<void> release(FolderGrant grant) async {
    if (failRelease) {
      throw StateError('Grant storage unavailable');
    }

    released.add(grant.key);
  }
}

class MemoryTarget implements FolderImportTarget {
  final saved = <String, Book>{};
  final copies = <String, Uint8List>{};
  final memberships = <String, String>{};
  final identities = <String>[];
  bool failAfterPersist = false;
  Completer<void>? processing;
  Completer<void>? started;
  bool current = true;

  @override
  bool get isCurrent => current;

  @override
  List<Book> get books => saved.values.toList();

  @override
  Future<Book?> getBook(String id) async => saved[id];

  @override
  Future<Uint8List?> readStored(String id) async => copies[id];

  @override
  Future<BookImportResult> process(Uint8List bytes, String filename, String id) async {
    identities.add(id);
    copies[id] = bytes;
    started?.complete();
    started = null;
    await processing?.future;
    return BookImportResult(
      bookId: id,
      title: filename,
      author: 'Author',
      fileSize: bytes.length,
      fileHash: sha256.convert(bytes).toString(),
      fileExtension: filename.split('.').last,
    );
  }

  @override
  Future<void> finish(BookImportResult result, String filename, String? shelfId) async {
    saved.putIfAbsent(
      result.bookId,
      () => Book(
        id: result.bookId,
        title: result.title,
        author: result.author,
        fileHash: result.fileHash,
        addedAt: DateTime(2026),
      ),
    );

    if (failAfterPersist) {
      throw StateError('Queue persistence failed');
    }

    if (shelfId != null) {
      memberships[result.bookId] = shelfId;
    }
  }

  @override
  Future<void> ensureCopy(Book book, Uint8List bytes, String extension, String? shelfId) async {
    copies.putIfAbsent(book.id, () => bytes);

    if (shelfId != null) {
      memberships[book.id] = shelfId;
    }
  }

  @override
  Future<void> deleteStaged(String id) async => copies.remove(id);
}

class _FolderRepository extends FolderRepository {
  _FolderRepository(super.database);

  String? rejectedName;
  bool rejectReplacement = false;

  @override
  Future<void> replaceGrant(WatchedFolder folder, FolderGrant previous) async {
    if (rejectReplacement) {
      throw StateError('Folder could not be saved');
    }

    await super.replaceGrant(folder, previous);
  }

  @override
  Future<void> saveFolder(WatchedFolder folder) async {
    if (rejectedName != null && folder.name == rejectedName) {
      throw StateError('Folder could not be saved');
    }

    await super.saveFolder(folder);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late WatchedFolders folders;
  late MemoryAccess access;
  late MemoryTarget target;
  late _FolderRepository repository;
  var ready = true;
  var clockOffset = Duration.zero;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('papyrus-folder-test-');
    access = MemoryAccess();
    target = MemoryTarget();
    ready = true;
    clockOffset = Duration.zero;
    folders = WatchedFolders(
      access: access,
      captureTarget: () => target,
      libraryReady: () => ready,
      stabilityDelay: Duration.zero,
      pollInterval: const Duration(days: 1),
      now: () => DateTime.now().add(clockOffset),
      openRepository: (scope) async {
        repository = _FolderRepository(
          (await FolderRepository.open(scope, databasePath: '${temporary.path}/$scope.db')).database,
        );
        return repository;
      },
    );
    await folders.activate('guest');
    await folders.waitUntilIdle();
  });

  tearDown(() async {
    await folders.activate(null);
    folders.dispose();
    await temporary.delete(recursive: true);
  });

  Future<WatchedFolder> connect({String? shelf}) async {
    await folders.connect(grant, shelfId: shelf);
    await folders.waitUntilIdle();
    return folders.folders.single;
  }

  test('import progress has a fixed candidate total and reads one book at a time', () async {
    access.put('existing.epub', [1]);
    final folder = await connect();
    access.put('new.epub', [2]);
    access.put('another.pdf', [3]);
    access.put('duplicate.epub', [2]);
    access.put('cover.jpg', [4]);
    final observed = <(int, int)>[];
    folders.addListener(() {
      final progress = folder.progress;

      if (progress != null) {
        expect(progress.fraction, inInclusiveRange(0, 1));
        observed.add((progress.processed, progress.total));
      }
    });
    target.processing = Completer<void>();
    final started = target.started = Completer<void>();
    final scan = folders.scanNow(folder.id);
    await started.future;
    expect(folder.status, FolderStatus.importing);
    expect(folder.progress!.total, 3);
    expect(folder.progress!.processed, 0);
    expect(folder.progress!.remaining, 3);
    expect(access.reads, 2, reason: 'Only the original book and the current candidate have been read.');
    target.processing!.complete();
    await scan;
    expect(observed.toSet(), {(0, 3), (1, 3), (2, 3), (3, 3)});
    expect(folder.progress, isNull);
    expect(target.books, hasLength(3));
    expect(folder.duplicates, 1);
    observed.clear();
    await folders.scanNow(folder.id);
    expect(observed, isEmpty, reason: 'Unchanged books do not create another import batch.');
  });

  test('failed imports and recovered jobs advance progress without double counting source files', () async {
    final folder = await connect();
    access.put('first.epub', [1]);
    access.put('second.epub', [2]);
    target.failAfterPersist = true;
    final observed = <(int, int)>[];
    folders.addListener(() {
      final progress = folder.progress;

      if (progress != null) {
        observed.add((progress.processed, progress.total));
      }
    });
    await folders.scanNow(folder.id);
    expect(observed.toSet(), {(0, 2), (1, 2), (2, 2)});
    expect(folder.status, FolderStatus.attention);
    expect(folder.progress, isNull);
    observed.clear();
    target.failAfterPersist = false;
    await folders.retry(folder);
    await folders.waitUntilIdle();
    expect(observed.toSet(), {(0, 2), (1, 2), (2, 2)});
    expect(await repository.records('jobs'), isEmpty);
    expect(target.books, hasLength(2));
  });

  test('custom names persist independently of source access and survive reconnecting', () async {
    await folders.connect(grant, name: '  Reading inbox  ');
    await folders.waitUntilIdle();
    final folder = folders.folders.single;
    expect(folder.name, 'Reading inbox');
    expect(folder.grant.location, '/Books');
    await folders.update(folder, name: 'Research');
    await folders.waitUntilIdle();
    await folders.activate(null);
    await folders.activate('guest');
    await folders.waitUntilIdle();
    final restored = folders.folders.single;
    expect(restored.name, 'Research');
    expect(restored.grant.identity, grant.identity);
    await folders.replaceGrant(
      restored,
      const FolderGrant(key: 'new', identity: 'new', name: 'Moved books', location: '/Volumes/Drive/Books'),
    );
    await folders.waitUntilIdle();
    expect(restored.name, 'Research');
    expect((await repository.folders()).single.name, 'Research');
    expect(restored.grant.location, '/Volumes/Drive/Books');
  });

  test('a failed name save leaves the prior name intact and can be retried', () async {
    final folder = await connect();
    repository.rejectedName = 'Research';
    await expectLater(folders.update(folder, name: 'Research'), throwsStateError);
    expect(folder.name, 'Books');
    expect((await repository.folders()).single.name, 'Books');
    repository.rejectedName = null;
    await folders.update(folder, name: 'Research');
    expect(folder.name, 'Research');
    expect((await repository.folders()).single.name, 'Research');
  });

  test('blank names are rejected without changing the saved connection', () async {
    await expectLater(folders.connect(grant, name: '   '), throwsArgumentError);
    expect(await repository.folders(), isEmpty);
    final folder = await connect();
    await expectLater(folders.update(folder, name: '   '), throwsArgumentError);
    expect(folder.name, 'Books');
    expect((await repository.folders()).single.name, 'Books');
  });

  test('preview is read only and imports supported files lazily', () async {
    access.put('book.epub', [1, 2, 3]);
    access.put('nested/book.pdf', [4, 5]);
    access.put('cover.jpg', [6]);
    final preview = await folders.preview(grant, true);
    expect(preview.supported, 2);
    expect(preview.unsupported, 1);
    expect(preview.bytes, 5);
    expect(await repository.folders(), isEmpty);
    expect(access.reads, 0);
    await connect(shelf: 'reading');
    expect(target.books, hasLength(2));
    expect(target.memberships.values, everyElement('reading'));
    expect(access.reads, 2);
  });

  test('changed recursion persists and applies only to future discoveries', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    await folders.update(folder, recursive: false);
    await folders.waitUntilIdle();
    access.put('nested/new.pdf', [2]);
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(1));
    await folders.activate(null);
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(folders.folders.single.recursive, isFalse);
    await folders.update(folders.folders.single, recursive: true);
    await folders.waitUntilIdle();
    expect(target.books, hasLength(2));
  });

  test('rescans and reopening do not reparse unchanged books', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    await folders.scanNow(folder.id);
    expect(target.identities, hasLength(1));
    expect(access.reads, 1);
    await folders.activate(null);
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(target.books, hasLength(1));
    expect(target.identities, hasLength(1));
  });

  test('new files import and source deletion retains copies', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    access.files.clear();
    access.put('new.pdf', [2]);
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(2));
    expect(target.copies, hasLength(2));
  });

  test('identical files and renames associate with one book', () async {
    access.put('book.epub', [1]);
    access.put('other.epub', [1]);
    final folder = await connect();
    expect(target.books, hasLength(1));
    access.files.remove('book.epub');
    access.put('renamed.epub', [1]);
    await folders.scanNow(folder.id);
    expect(target.identities, hasLength(1));
    expect(target.books, hasLength(1));
  });

  test('changed content requires review and preserves existing book', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    final original = target.books.single;
    access.put('book.epub', [2]);
    await folders.scanNow(folder.id);
    final issue = (await folders.issues(folder.id)).single;
    expect(issue['state'], 'changed');
    expect(target.books.single, same(original));
    await folders.review(folder, issue, import: true);
    await folders.waitUntilIdle();
    expect(target.books, hasLength(2));
    expect(target.saved[original.id], same(original));
    await folders.activate(null);
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(folders.bookIds(folder.id), containsAll(target.saved.keys));
  });

  test('unknown provider size imports and unknown timestamps detect same-size changes', () async {
    access.reportedSize = -1;
    access.reportedModified = 0;
    access.put('book.epub', [1, 2]);
    final preview = await folders.preview(grant, true);
    expect(preview.bytes, 0);
    expect(preview.unknownSizes, 1);
    final folder = await connect();
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(1));
    final processed = target.identities.length;
    await folders.scanNow(folder.id);
    expect(target.identities, hasLength(processed));
    access.put('book.epub', [3, 4]);
    await folders.scanNow(folder.id);
    expect((await folders.issues(folder.id)).single['state'], 'changed');
    expect(target.books, hasLength(1));
  });

  test('future source timestamps use repeated observation instead of deferring forever', () async {
    access.reportedModified = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
    access.put('book.epub', [1]);
    final folder = await connect();
    expect(target.books, isEmpty);
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(1));
  });

  for (final condition in ['recent', 'missing timestamp', 'future timestamp', 'changed during read']) {
    test('one-time selections finish files deferred for $condition before pausing', () async {
      await folders.activate(null);
      folders.dispose();
      var now = DateTime.now();
      folders = WatchedFolders(
        access: access,
        captureTarget: () => target,
        libraryReady: () => ready,
        now: () => now,
        pollInterval: const Duration(days: 1),
        openRepository: (scope) => FolderRepository.open(scope, databasePath: '${temporary.path}/$scope.db'),
      );
      await folders.activate('guest');
      await folders.waitUntilIdle();
      access.put('book.epub', [1]);

      switch (condition) {
        case 'recent':
          access.reportedModified = now.millisecondsSinceEpoch;
        case 'missing timestamp':
          access.reportedModified = 0;
        case 'future timestamp':
          access.reportedModified = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
        case 'changed during read':
          access.afterRead = () {
            access.afterRead = null;
            access.put('book.epub', [2]);
          };
      }

      const selection = FolderGrant(
        key: 'selection',
        identity: 'selection',
        name: 'Books',
        location: 'Books',
        persistent: false,
      );
      await folders.connect(selection);
      await folders.waitUntilIdle();
      final folder = folders.folders.single;
      expect(target.books, isEmpty);
      expect(folder.enabled, isTrue, reason: 'Deferred files must remain eligible for automatic scans');
      now = now.add(const Duration(seconds: 3));
      folders.schedule();
      await folders.waitUntilIdle();
      expect(target.books, hasLength(1));
      expect(target.copies.values.single, condition == 'changed during read' ? [2] : [1]);
      expect(folder.enabled, isFalse);
      expect(folder.status, FolderStatus.paused);
      access.put('later.pdf', [3]);
      folders.schedule();
      await folders.waitUntilIdle();
      expect(target.books, hasLength(1), reason: 'Completed one-time selections must not watch later additions');
    });
  }

  test('failed grant replacement retains the saved connection', () async {
    final folder = await connect();
    repository.rejectReplacement = true;
    const replacement = FolderGrant(key: 'new', identity: 'root', name: 'Books', location: '/Books');
    await expectLater(folders.replaceGrant(folder, replacement), throwsStateError);
    await folders.waitUntilIdle();
    expect(folder.grant.key, grant.key);
    expect((await repository.folders()).single.grant.key, grant.key);
    expect(access.released, isEmpty);
  });

  test('grant cleanup failures survive replacement and restart without revoking the new grant', () async {
    final folder = await connect();
    access.failRelease = true;
    const replacement = FolderGrant(key: 'new', identity: 'root', name: 'Books', location: '/Books');
    await folders.replaceGrant(folder, replacement);
    await folders.waitUntilIdle();
    expect(folder.grant.key, replacement.key);
    expect((await repository.retiredGrants()).single.key, grant.key);
    await folders.activate(null);
    access.failRelease = false;
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(await repository.retiredGrants(), isEmpty);
    expect(access.released, [grant.key]);
    expect(folders.folders.single.grant.key, replacement.key);
  });

  test('stopping journals failed permission cleanup without losing imported books', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    access.failRelease = true;
    await folders.stop(folder);
    await folders.waitUntilIdle();
    expect(folders.folders, isEmpty);
    expect(target.books, hasLength(1));
    expect((await repository.retiredGrants()).single.key, grant.key);
    access.failRelease = false;
    folders.schedule();
    await folders.waitUntilIdle();
    expect(await repository.retiredGrants(), isEmpty);
  });

  test('keep existing remembers a changed version', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    access.put('book.epub', [2]);
    await folders.scanNow(folder.id);
    await folders.review(folder, (await folders.issues(folder.id)).single, import: false);
    await folders.waitUntilIdle();
    await folders.scanNow(folder.id);
    expect(await folders.issues(folder.id), isEmpty);
    expect(target.books, hasLength(1));
  });

  test('user deletion suppresses renamed copies until explicit reimport', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    final book = target.books.single;
    await folders.recordDeletion(book.id, book.fileHash);
    target.saved.clear();
    access.put('renamed.epub', [1]);
    await folders.scanNow(folder.id);
    expect(target.books, isEmpty);
    final issue = (await folders.issues(folder.id)).first;
    await folders.review(folder, issue, import: true);
    await folders.waitUntilIdle();
    expect(target.books, hasLength(1));
    expect(target.books.single.id, isNot(book.id));
  });

  test('explicit reimport does not reuse a deleted identity referenced by a paused overlapping folder', () async {
    access.put('book.epub', [1]);
    final first = await connect();
    final original = target.books.single;
    const overlap = FolderGrant(key: 'overlap', identity: 'overlap', name: 'Overlap', location: '/Books/overlap');
    await folders.connect(overlap);
    await folders.waitUntilIdle();
    final second = folders.folders.singleWhere((folder) => folder.id != first.id);
    await folders.update(second, enabled: false);
    await folders.waitUntilIdle();
    await folders.recordDeletion(original.id, original.fileHash);
    await folders.waitUntilIdle();
    target.saved.clear();
    await folders.scanNow(first.id);
    await folders.review(first, (await folders.issues(first.id)).single, import: true);
    await folders.waitUntilIdle();
    expect(target.books.single.id, isNot(original.id));
  });

  test('failed queue after metadata commit retries with the same identity', () async {
    access.put('book.epub', [1]);
    target.failAfterPersist = true;
    final folder = await connect();
    final id = target.books.single.id;
    expect((await folders.issues(folder.id)).single['state'], 'failed');
    target.failAfterPersist = false;
    await folders.retry(folder);
    await folders.waitUntilIdle();
    expect(target.books.single.id, id);
    expect(target.identities, everyElement(id));
    expect(await repository.records('jobs'), isEmpty);
    expect(await folders.issues(folder.id), isEmpty);
  });

  test('prepared copy recovers after source access is lost and app reopens', () async {
    access.put('book.epub', [1]);
    target.failAfterPersist = true;
    final folder = await connect();
    final job = (await repository.records('jobs')).single;
    job['state'] = 'prepared';
    await repository.save('jobs', job['recordId'] as String, job, folderId: folder.id);
    access.files.clear();
    access.failure = 'access';
    target.failAfterPersist = false;
    await folders.activate(null);
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(target.books, hasLength(1));
    expect(await repository.records('jobs'), isEmpty);
    expect(folders.folders.single.status, FolderStatus.accessNeeded);
    expect(folders.folders.single.progress, isNull);
  });

  test('a changed source keeps the original book and its failed upload journal', () async {
    access.put('book.epub', [1]);
    target.failAfterPersist = true;
    final folder = await connect();
    final original = target.books.single;
    access.put('book.epub', [2]);
    await folders.scanNow(folder.id);
    final changed = (await folders.issues(folder.id)).single;
    expect(changed['state'], 'changed');
    target.failAfterPersist = false;
    await folders.review(folder, changed, import: true);
    await folders.waitUntilIdle();
    expect(target.books, hasLength(2));
    expect(target.copies[original.id], [1]);
    expect(await repository.records('jobs'), hasLength(1));
    await folders.retry(folder);
    await folders.waitUntilIdle();
    expect(await repository.records('jobs'), isEmpty);
    expect(target.copies[original.id], [1]);
    expect(target.books, hasLength(2));
  });

  test('profile switch during parsing cannot commit to either library', () async {
    access.put('book.epub', [1]);
    target.processing = Completer<void>();
    target.started = Completer<void>();
    final started = target.started!.future;
    await folders.connect(grant);
    await started;
    final switching = folders.activate('other');
    target.processing!.complete();
    await switching;
    expect(target.books, isEmpty);
    expect(folders.folders, isEmpty);
    target.processing = null;
    await folders.activate('guest');
    await folders.waitUntilIdle();
    expect(target.books, hasLength(1));
  });

  test('work resumed after lease expiry cannot commit before reacquiring the lease', () async {
    access.put('book.epub', [1]);
    target.processing = Completer<void>();
    target.started = Completer<void>();
    final started = target.started!.future;
    await folders.connect(grant);
    await started;
    clockOffset = const Duration(minutes: 3);
    target.processing!.complete();
    await folders.waitUntilIdle();
    expect(target.books, isEmpty);
    expect(await repository.records('jobs'), hasLength(1));
    target.processing = null;
    await folders.scanNow(folders.folders.single.id);
    expect(target.books, hasLength(1));
    expect(await repository.records('jobs'), isEmpty);
  });

  test('permission loss is recoverable and does not remove imported books', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    access.failure = 'access';
    await folders.scanNow(folder.id);
    expect(folder.status, FolderStatus.accessNeeded);
    expect(target.books, hasLength(1));
    access.failure = null;
    await folders.reconnect(folder);
    await folders.waitUntilIdle();
    expect(folder.status, FolderStatus.upToDate);
  });

  test('files changing while read are deferred', () async {
    access.put('book.epub', [1]);
    access.afterRead = () => access.put('book.epub', [2, 3]);
    final folder = await connect();
    expect(target.books, isEmpty);
    access.afterRead = null;
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(1));
  });

  test('paused folders and unavailable libraries do not import', () async {
    final folder = await connect();
    await folders.update(folder, enabled: false);
    access.put('book.epub', [1]);
    await folders.scanNow(folder.id);
    expect(target.books, isEmpty);
    ready = false;
    await folders.update(folder, enabled: true);
    await folders.scanNow(folder.id);
    expect(target.books, isEmpty);
    ready = true;
    await folders.scanNow(folder.id);
    expect(target.books, hasLength(1));
  });

  test('stop watching retains books and clear removes connections', () async {
    access.put('book.epub', [1]);
    final folder = await connect();
    await folders.stop(folder);
    expect(target.books, hasLength(1));
    expect(await repository.folders(), isEmpty);
    await connect();
    await folders.clear();
    folders.resume();
    expect(await repository.folders(), isEmpty);
    expect(target.books, hasLength(1));
  });

  test('a persisted lease excludes a second window and expires', () async {
    final now = DateTime.now();
    expect(await repository.acquire('first', now), isTrue);
    expect(await repository.acquire('second', now), isFalse);
    await repository.release('second');
    expect(await repository.acquire('second', now), isFalse);
    expect(await repository.acquire('second', now.add(const Duration(minutes: 3))), isTrue);
  });

  test('a second window observes pause and removal without recreating the connection', () async {
    final folder = await connect();
    final other = WatchedFolders(
      access: access,
      captureTarget: () => target,
      libraryReady: () => true,
      stabilityDelay: Duration.zero,
      pollInterval: const Duration(days: 1),
      openRepository: (scope) => FolderRepository.open(scope, databasePath: '${temporary.path}/$scope.db'),
    );

    try {
      await other.activate('guest');
      await other.waitUntilIdle();
      await folders.update(folder, enabled: false);
      await folders.waitUntilIdle();
      access.put('later.epub', [1]);
      await other.scanNow(folder.id);
      expect(target.books, isEmpty);
      expect(other.folders.single.enabled, isFalse);
      await folders.stop(folder);
      await folders.waitUntilIdle();
      await other.scanNow(folder.id);
      expect(other.folders, isEmpty);
      expect(await repository.folders(), isEmpty);
    } finally {
      await other.activate(null);
      other.dispose();
    }
  });

  test('a duplicate connection is rejected after reopening the shared database', () async {
    await connect();
    await expectLater(folders.connect(grant), throwsStateError);
    await folders.waitUntilIdle();
    expect(await repository.folders(), hasLength(1));
  });

  test('large import discovery cancels before reading file contents', () async {
    final folder = await connect();

    for (var index = 0; index < 10000; index++) {
      access.put('$index.epub', [1]);
    }

    access.afterEnumerate = () {
      if (access.enumerated == 10) {
        folders.invalidate();
      }
    };
    await folders.scanNow(folder.id);
    expect(access.enumerated, 10);
    expect(access.reads, 0);
    expect(folder.progress, isNull);
    expect(target.books, isEmpty);
  });

  test('large preview streams metadata without loading file contents and can cancel', () async {
    for (var index = 0; index < 10000; index++) {
      access.put('$index.epub', [1]);
    }

    final preview = await folders.preview(grant, true);
    expect(preview.supported, 10000);
    expect(access.reads, 0);
    access.enumerated = 0;
    await folders.preview(grant, true, cancelled: () => access.enumerated >= 10);
    expect(access.enumerated, 10);
    expect(access.reads, 0);
  });
}
