import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_delete_cleanup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('deleteBookWithMediaCleanup removes queued uploads and cached file before deleting book', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final queue = MediaUploadQueue(prefs);
    final book = Book(id: 'book-1', title: 'Book', author: 'Author', addedAt: DateTime.utc(2026));
    final deletedLocalFiles = <String>[];

    await repository.upsert(book);
    await pumpEventQueue();
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await deleteBookWithMediaCleanup(
      dataStore: dataStore,
      mediaUploadQueue: queue,
      bookId: book.id,
      deleteBookFile: (bookId) async => deletedLocalFiles.add(bookId),
    );
    await pumpEventQueue();

    expect(queue.pendingTasks, isEmpty);
    expect(deletedLocalFiles, [book.id]);
    expect(dataStore.getBook(book.id), isNull);
    expect(await repository.getById(book.id), isNull);
  });
}
