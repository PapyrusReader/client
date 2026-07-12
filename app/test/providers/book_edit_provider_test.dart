import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/book_edit_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  test('loads from repository before the in-memory cache hydrates', () async {
    final storedBook = buildTestBook(id: 'repository-book', title: 'Stored Book');
    final dataStore = DataStore(bookRepository: _LookupBookRepository(storedBook));
    final provider = BookEditProvider()..setDataStore(dataStore);

    await provider.loadBook(storedBook.id);

    expect(provider.editedBook, storedBook);
    expect(provider.error, isNull);
  });

  test('waits for the first repository snapshot before reporting a missing book', () async {
    final storedBook = buildTestBook(id: 'delayed-book', title: 'Delayed Book');
    final repository = _DelayedSnapshotBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final provider = BookEditProvider()..setDataStore(dataStore);

    final load = provider.loadBook(storedBook.id);
    await Future<void>.delayed(Duration.zero);

    expect(provider.isLoading, isTrue);
    expect(provider.error, isNull);

    repository.controller.add([storedBook]);
    await load;

    expect(provider.editedBook, storedBook);
    expect(provider.error, isNull);
    await dataStore.disposeBookRepository();
    await repository.controller.close();
  });

  test('saving a picked cover keeps image bytes out of synced book metadata', () async {
    final dataStore = DataStore();
    final original = buildTestBook(
      id: 'book-1',
      coverUrl: 'https://example.com/original.jpg',
    ).copyWith(coverMediaId: 'original-cover');
    dataStore.addBook(original);

    final provider = BookEditProvider()..setDataStore(dataStore);
    await provider.loadBook(original.id);
    provider.updateCoverFromFile(Uint8List.fromList([1, 2, 3]));

    expect(await provider.save(), isTrue);

    final saved = dataStore.getBook(original.id)!;
    expect(saved.coverUrl, isNull);
    expect(saved.coverMediaId, 'original-cover');
    expect(provider.coverImageBytes, isNull);
  });

  test('save waits for synced metadata persistence before completing', () async {
    final repository = _GatedBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final original = buildTestBook(id: 'book-1');
    dataStore.replaceBooksFromSync([original]);
    final provider = BookEditProvider()..setDataStore(dataStore);
    await provider.loadBook(original.id);
    provider.updateTitle('Updated title');

    var completed = false;
    final save = provider.save().then((result) {
      completed = true;
      return result;
    });
    await repository.upsertStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    repository.allowUpsert.complete();
    expect(await save, isTrue);
  });
}

class _LookupBookRepository implements BookRepository {
  _LookupBookRepository(this.book);

  final Book book;

  @override
  Stream<List<Book>> watchAll() => const Stream.empty();

  @override
  Future<Book?> getById(String id) async => id == book.id ? book : null;

  @override
  Future<void> upsert(Book book) async {}

  @override
  Future<void> delete(String id) async {}
}

class _DelayedSnapshotBookRepository implements BookRepository {
  final controller = StreamController<List<Book>>.broadcast();

  @override
  Stream<List<Book>> watchAll() => controller.stream;

  @override
  Future<Book?> getById(String id) async => null;

  @override
  Future<void> upsert(Book book) async {}

  @override
  Future<void> delete(String id) async {}
}

class _GatedBookRepository implements BookRepository {
  final upsertStarted = Completer<void>();
  final allowUpsert = Completer<void>();

  @override
  Stream<List<Book>> watchAll() => const Stream.empty();

  @override
  Future<Book?> getById(String id) async => null;

  @override
  Future<void> upsert(Book book) async {
    upsertStarted.complete();
    await allowUpsert.future;
  }

  @override
  Future<void> delete(String id) async {}
}
