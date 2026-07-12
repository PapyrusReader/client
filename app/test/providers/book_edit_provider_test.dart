import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/book_edit_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
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
