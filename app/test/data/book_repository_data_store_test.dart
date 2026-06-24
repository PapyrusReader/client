import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/book.dart';

class FakeBookRepository implements BookRepository {
  final StreamController<List<Book>> controller = StreamController<List<Book>>.broadcast();
  final List<Book> upserts = [];
  final List<String> deletes = [];

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
  }

  @override
  Future<Book?> getById(String id) async {
    return upserts.where((book) => book.id == id).firstOrNull;
  }

  @override
  Future<void> upsert(Book book) async {
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
}
