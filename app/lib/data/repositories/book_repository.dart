import 'dart:async';

import 'package:papyrus/models/book.dart';

abstract interface class BookRepository {
  Stream<List<Book>> watchAll();

  Future<Book?> getById(String id);

  Future<void> upsert(Book book);

  Future<void> delete(String id);
}

class InMemoryBookRepository implements BookRepository {
  final Map<String, Book> _books = {};
  final StreamController<List<Book>> _changes = StreamController<List<Book>>.broadcast(sync: true);

  @override
  Stream<List<Book>> watchAll() async* {
    yield _snapshot;
    yield* _changes.stream;
  }

  @override
  Future<Book?> getById(String id) async => _books[id];

  @override
  Future<void> upsert(Book book) async {
    _books[book.id] = book;
    _changes.add(_snapshot);
  }

  @override
  Future<void> delete(String id) async {
    _books.remove(id);
    _changes.add(_snapshot);
  }

  void replaceAll(Iterable<Book> books) {
    _books
      ..clear()
      ..addEntries(books.map((book) => MapEntry(book.id, book)));
  }

  List<Book> get _snapshot => List.unmodifiable(_books.values);
}
