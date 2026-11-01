import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_session.dart';
import 'package:papyrus/services/book_import_service_stub.dart';

class _Repository extends Fake implements BookRepository {}

class _DataStore extends Fake implements DataStore {
  final repository = _Repository();

  @override
  BookRepository requireBookRepository() => repository;

  @override
  bool isBookRepositoryCurrent(BookRepository repository) => identical(this.repository, repository);
}

class _Auth extends Fake implements AuthProvider {
  _Auth({this.guest = false});
  final bool guest;

  @override
  bool isDeletingGuestAccount = false;

  @override
  bool get isSignedIn => !guest;

  @override
  bool get isOfflineMode => guest;

  @override
  PapyrusUser? get user => guest ? null : PapyrusUser.fromJson({'user_id': 'bob', 'connected_providers': <String>[]});
}

class _Queue extends Fake implements MediaUploadQueue {
  _Queue({this.guest = false});
  final bool guest;

  @override
  MediaStorageScope? get activeScope => guest ? null : MediaStorageScope(profileKey: 'official', userId: 'alice');
}

class _Database extends Fake implements PapyrusPowerSyncService {
  _Database(this.mode);

  @override
  final LibraryDatabaseMode mode;
}

class _Importer extends Fake implements BookImportService {}

class _ImportStorage extends Fake implements BookImportService {
  final covers = <String, Uint8List>{};
  final stored = Completer<void>();
  Completer<void>? pause;

  @override
  Future<void> storePendingCoverFile(MediaStorageScope scope, String bookId, Uint8List bytes) async {
    covers['${scope.persistenceKey}:$bookId'] = bytes;
    if (!stored.isCompleted) {
      stored.complete();
    }

    await pause?.future;
  }

  @override
  Future<void> deletePendingCoverFile(MediaStorageScope scope, String bookId) async {
    covers.remove('${scope.persistenceKey}:$bookId');
  }

  @override
  Future<void> storeGuestCoverFile(String bookId, Uint8List bytes) async {
    covers['guest:$bookId'] = bytes;
  }

  @override
  Future<void> deleteGuestCoverFile(String bookId) async {
    covers.remove('guest:$bookId');
  }
}

BookImportResult _result() => BookImportResult(
  bookId: 'book',
  title: 'Imported',
  author: 'Author',
  fileSize: 3,
  fileHash: 'hash',
  fileExtension: 'epub',
  coverImage: Uint8List.fromList([1, 2, 3]),
  coverMimeType: 'image/png',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final guest in [false, true]) {
    test('captured ${guest ? 'guest' : 'account'} session persists metadata and cover to its destination', () async {
      final repository = InMemoryBookRepository();
      final store = DataStore(bookRepository: repository);
      final queue = MediaUploadQueue(await SharedPreferences.getInstance());
      final storage = _ImportStorage();
      final scope = MediaStorageScope(profileKey: 'official', userId: 'bob');

      if (!guest) {
        await queue.activateScope(scope);
      }

      final session = BookImportSession.capture(
        dataStore: store,
        queue: queue,
        importService: storage,
        authProvider: _Auth(guest: guest),
        powerSyncService: _Database(guest ? LibraryDatabaseMode.guest : LibraryDatabaseMode.authenticated),
      );

      final book = await session.commit(_result(), 'original.epub');
      expect((await repository.getById('book'))?.title, 'Imported');
      expect(book.coverUrl, isNull);
      expect(storage.covers[guest ? 'guest:book' : '${scope.persistenceKey}:book'], [1, 2, 3]);
      expect(queue.pendingTasks.length, guest ? 0 : 2);
      await store.disposeBookRepository();
      store.dispose();
      queue.dispose();
    });
  }

  test('switching repository and media scope during cover persistence cannot import into the new account', () async {
    final first = InMemoryBookRepository();
    final second = InMemoryBookRepository();
    final store = DataStore(bookRepository: first);
    final queue = MediaUploadQueue(await SharedPreferences.getInstance());
    final oldScope = MediaStorageScope(profileKey: 'official', userId: 'bob');
    final newScope = MediaStorageScope(profileKey: 'other', userId: 'bob');
    await queue.activateScope(oldScope);
    final storage = _ImportStorage()..pause = Completer<void>();
    storage.covers['${newScope.persistenceKey}:book'] = Uint8List.fromList([9]);

    final session = BookImportSession.capture(
      dataStore: store,
      queue: queue,
      importService: storage,
      authProvider: _Auth(),
      powerSyncService: _Database(LibraryDatabaseMode.authenticated),
    );

    final commit = session.commit(_result(), 'original.epub');
    final rejected = expectLater(commit, throwsStateError);
    await storage.stored.future;
    await store.attachBookRepository(second);
    await queue.activateScope(newScope);
    storage.pause!.complete();
    await rejected;
    expect(await first.getById('book'), isNull);
    expect(await second.getById('book'), isNull);
    expect(storage.covers['${oldScope.persistenceKey}:book'], isNull);
    expect(storage.covers['${newScope.persistenceKey}:book'], [9]);
    expect(queue.pendingTasks, isEmpty);
    await store.disposeBookRepository();
    store.dispose();
    queue.dispose();
  });
  test('guest deletion invalidates imports and prevents new sessions', () {
    final auth = _Auth(guest: true);

    BookImportSession capture() => BookImportSession.capture(
      dataStore: _DataStore(),
      queue: _Queue(guest: true),
      importService: _Importer(),
      authProvider: auth,
      powerSyncService: _Database(LibraryDatabaseMode.guest),
    );

    final session = capture();
    expect(session.isCurrent(), isTrue);
    auth.isDeletingGuestAccount = true;
    expect(session.isCurrent(), isFalse);
    expect(capture, throwsStateError);
  });

  test('cannot capture the previous account media scope during account activation', () {
    expect(
      () => BookImportSession.capture(
        dataStore: _DataStore(),
        queue: _Queue(),
        importService: _Importer(),
        authProvider: _Auth(),
        powerSyncService: _Database(LibraryDatabaseMode.authenticated),
      ),
      throwsStateError,
    );
  });

  test('cannot capture a guest database while an authenticated account is activating', () {
    expect(
      () => BookImportSession.capture(
        dataStore: _DataStore(),
        queue: _Queue(),
        importService: _Importer(),
        authProvider: _Auth(),
        powerSyncService: _Database(LibraryDatabaseMode.guest),
      ),
      throwsStateError,
    );
  });
}
