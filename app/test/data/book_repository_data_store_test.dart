import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBookRepository implements BookRepository {
  final StreamController<List<Book>> controller = StreamController<List<Book>>.broadcast();
  final List<Book> upserts = [];
  final List<String> deletes = [];
  Completer<void>? upsertGate;
  Completer<void>? deleteGate;
  Object? upsertError;
  Object? deleteError;

  @override
  Future<void> delete(String id) async {
    await deleteGate?.future;
    if (deleteError != null) throw deleteError!;
    deletes.add(id);
  }

  @override
  Future<Book?> getById(String id) async {
    return upserts.where((book) => book.id == id).firstOrNull;
  }

  @override
  Future<void> upsert(Book book) async {
    await upsertGate?.future;
    if (upsertError != null) throw upsertError!;
    upserts.add(book);
  }

  @override
  Stream<List<Book>> watchAll() => controller.stream;
}

Book _book(String id, String title) {
  return Book(id: id, title: title, author: 'Author', addedAt: DateTime.utc(2026, 1, 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('repository stream is the source of the DataStore book snapshot', () async {
    final repository = FakeBookRepository();
    final store = DataStore();

    await store.attachBookRepository(repository);
    repository.controller.add([_book('one', 'First')]);
    await pumpEventQueue();

    expect(store.books.map((book) => book.title), ['First']);

    repository.controller.add([_book('two', 'Second')]);
    await pumpEventQueue();

    expect(store.books.map((book) => book.title), ['Second']);
    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('attaching a repository stays loading until its first snapshot', () async {
    final repository = FakeBookRepository();
    final store = DataStore()..loadData(books: [_book('old', 'Old book')]);
    expect(store.isLoaded, isTrue);

    await store.attachBookRepository(repository);

    expect(store.isLoaded, isFalse);
    repository.controller.add(const []);
    await pumpEventQueue();
    expect(store.isLoaded, isTrue);

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('waitUntilLoaded completes only after the first repository snapshot', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    var completed = false;

    final loaded = store.waitUntilLoaded().then((_) => completed = true);
    await pumpEventQueue();
    expect(completed, isFalse);

    repository.controller.add([_book('one', 'First')]);
    await loaded;

    expect(store.isLoaded, isTrue);
    expect(store.getBook('one')?.title, 'First');
    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('stale sync snapshots do not clear an uploaded cover media id', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    final syncedBook = _book('one', 'First');

    repository.controller.add([syncedBook]);
    await pumpEventQueue();

    store.updateBook(syncedBook.copyWith(coverMediaId: 'cover-asset'));
    repository.controller.add([syncedBook]);
    await pumpEventQueue();

    expect(store.getBook(syncedBook.id)?.coverMediaId, 'cover-asset');

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('book mutations delegate to the active repository', () async {
    final repository = FakeBookRepository();
    final store = DataStore();
    final book = _book('one', 'First');

    await store.attachBookRepository(repository);
    store.addBook(book);
    store.updateBook(book.copyWith(title: 'Updated'));
    store.deleteBook(book.id);
    await pumpEventQueue();

    expect(repository.upserts.map((item) => item.title), ['First', 'Updated']);
    expect(repository.deletes, ['one']);
    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('legacy addBook updates the snapshot and notifies listeners before returning', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    final book = _book('one', 'First');
    var notifications = 0;
    store.addListener(() => notifications++);

    store.addBook(book);

    expect(store.getBook(book.id), same(book));
    expect(notifications, 1);

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('legacy addBook and deleteBook reject a missing repository synchronously', () async {
    final store = DataStore();
    await store.disposeBookRepository();

    expect(() => store.addBook(_book('one', 'First')), throwsStateError);
    expect(() => store.deleteBook('one'), throwsStateError);
  });

  test('awaitable book mutations complete only after repository writes finish', () async {
    final repository = FakeBookRepository()
      ..upsertGate = Completer<void>()
      ..deleteGate = Completer<void>();
    final store = DataStore(bookRepository: repository);
    final book = _book('one', 'First');

    var addCompleted = false;
    final add = store.addBookAndWait(book).then((_) => addCompleted = true);
    await pumpEventQueue();
    expect(addCompleted, isFalse);
    repository.upsertGate!.complete();
    await add;
    expect(repository.upserts, [book]);

    var deleteCompleted = false;
    final delete = store.deleteBookAndWait(book.id).then((_) => deleteCompleted = true);
    await pumpEventQueue();
    expect(deleteCompleted, isFalse);
    repository.deleteGate!.complete();
    await delete;
    expect(repository.deletes, [book.id]);

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('awaitable book mutations surface repository errors', () async {
    final addFailure = StateError('upsert failed');
    final deleteFailure = StateError('delete failed');
    final repository = FakeBookRepository()
      ..upsertError = addFailure
      ..deleteError = deleteFailure;
    final store = DataStore(bookRepository: repository);

    await expectLater(store.addBookAndWait(_book('one', 'First')), throwsA(same(addFailure)));
    await expectLater(store.deleteBookAndWait('one'), throwsA(same(deleteFailure)));

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('repository-bound add is observable before a delayed watch stream emits', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    final captured = store.requireBookRepository();
    final book = _book('one', 'First');

    await store.addBookToRepositoryAndWait(captured, book);

    expect(store.isBookRepositoryCurrent(captured), isTrue);
    expect(store.getBook(book.id), same(book));

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('repository-bound delete targets captured repository after active repository changes', () async {
    final first = FakeBookRepository();
    final second = FakeBookRepository();
    final store = DataStore(bookRepository: first);
    final captured = store.requireBookRepository();
    final book = _book('one', 'First');
    await store.addBookToRepositoryAndWait(captured, book);
    await store.attachBookRepository(second);

    await store.deleteBookFromRepositoryAndWait(captured, book.id);

    expect(first.deletes, [book.id]);
    expect(second.deletes, isEmpty);
    expect(store.isBookRepositoryCurrent(captured), isFalse);

    await store.disposeBookRepository();
    await first.controller.close();
    await second.controller.close();
  });

  test('shelf cover previews retain the source book id', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    final book = _book('book-1', 'First');
    final createdAt = DateTime.utc(2026, 1, 1);
    final shelf = Shelf(id: 'shelf-1', name: 'Shelf', createdAt: createdAt, updatedAt: createdAt);

    store.addBook(book);
    store.addShelf(shelf);
    store.addBookToShelf(book.id, shelf.id);

    expect(store.getCoverPreviewsForShelf(shelf.id).single.bookId, book.id);

    await store.disposeBookRepository();
    await repository.controller.close();
  });

  test('immediate queue upload does not rewrite a repository-bound add', () async {
    final repository = FakeBookRepository();
    final store = DataStore(bookRepository: repository);
    final captured = store.requireBookRepository();
    final book = _book('one', 'First').copyWith(filePath: 'one.epub', fileSize: 3, fileHash: 'hash');
    await store.addBookToRepositoryAndWait(captured, book);
    final prefs = await SharedPreferences.getInstance();
    final queue = MediaUploadQueue(prefs);
    await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
    await queue.enqueueBookFile(book: book, filename: 'one.epub', contentType: 'application/epub+zip');

    await queue.processPending(
      dataStore: store,
      readBookFile: (_) async => Uint8List.fromList([1, 2, 3]),
      readPendingCover: (_, _) async => null,
      uploadMedia: (payload) async => MediaAsset(
        assetId: 'file-media',
        ownerUserId: 'user-1',
        bookId: payload.bookId,
        kind: MediaKind.bookFile,
        originalFilename: payload.filename,
        contentType: payload.contentType,
        extension: 'epub',
        sizeBytes: payload.bytes.length,
        sha256: 'hash',
        storagePath: 'books/file-media.epub',
      ),
    );

    expect(queue.pendingTasks, isEmpty);
    expect(store.getBook(book.id)?.fileMediaId, isNull);
    expect(store.getBook(book.id)?.fileHash, 'hash');
    await pumpEventQueue();
    expect(repository.upserts.last.fileMediaId, isNull);
    expect(repository.upserts.last.fileHash, 'hash');

    await store.disposeBookRepository();
    await repository.controller.close();
  });
}
