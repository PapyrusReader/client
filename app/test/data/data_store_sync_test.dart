import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';

class FakeBookSyncWriter implements BookSyncWriter {
  final upserts = <Book>[];
  final deletes = <String>[];

  @override
  Future<void> deleteBook(String id) async {
    deletes.add(id);
  }

  @override
  Future<void> upsertBook(Book book) async {
    upserts.add(book);
  }
}

void main() {
  test('DataStore delegates local book writes to sync writer', () {
    final dataStore = DataStore();
    final writer = FakeBookSyncWriter();
    final book = Book(
      id: '11111111-1111-1111-1111-111111111111',
      title: 'Book',
      author: 'Author',
      addedAt: DateTime(2026, 5, 9),
    );

    dataStore.attachBookSyncWriter(writer);
    dataStore.addBook(book);
    dataStore.updateBook(book.copyWith(title: 'Updated'));
    dataStore.deleteBook(book.id);

    expect(writer.upserts.map((book) => book.title), ['Book', 'Updated']);
    expect(writer.deletes, [book.id]);
  });

  test('replaceBooksFromSync updates books without delegating writes', () {
    final dataStore = DataStore();
    final writer = FakeBookSyncWriter();
    final book = Book(
      id: '11111111-1111-1111-1111-111111111111',
      title: 'Synced Book',
      author: 'Author',
      addedAt: DateTime(2026, 5, 9),
    );

    dataStore.attachBookSyncWriter(writer);
    dataStore.replaceBooksFromSync([book]);

    expect(dataStore.books.single.title, 'Synced Book');
    expect(writer.upserts, isEmpty);
    expect(writer.deletes, isEmpty);
  });
}
