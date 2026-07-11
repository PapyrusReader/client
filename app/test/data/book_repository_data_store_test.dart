import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/book.dart';

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
}
