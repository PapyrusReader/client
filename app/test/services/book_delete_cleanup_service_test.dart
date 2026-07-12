import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_delete_cleanup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('deleteBookWithMediaCleanup removes every local cover representation before deleting book', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final queue = MediaUploadQueue(prefs);
    await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
    final book = Book(
      id: 'book-1',
      title: 'Book',
      author: 'Author',
      coverMediaId: 'cover-1',
      addedAt: DateTime.utc(2026),
    );
    final deletedLocalFiles = <String>[];
    final deletedCovers = <String>[];

    await repository.upsert(book);
    await pumpEventQueue();
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await deleteBookWithMediaCleanup(
      dataStore: dataStore,
      mediaUploadQueue: queue,
      bookId: book.id,
      coverMediaId: book.coverMediaId,
      deleteBookFile: (bookId) async => deletedLocalFiles.add(bookId),
      deletePendingCover: (bookId) async => deletedCovers.add('pending:$bookId'),
      deleteGuestCover: (bookId) async => deletedCovers.add('guest:$bookId'),
      deleteCoverFile: (mediaId) async => deletedCovers.add('cached:$mediaId'),
    );
    await pumpEventQueue();

    expect(queue.pendingTasks, isEmpty);
    expect(deletedLocalFiles, [book.id]);
    expect(deletedCovers, ['pending:${book.id}', 'guest:${book.id}', 'cached:cover-1']);
    expect(dataStore.getBook(book.id), isNull);
    expect(await repository.getById(book.id), isNull);
  });
}
