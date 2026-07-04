import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';

typedef DeleteBookFile = Future<void> Function(String bookId);

Future<void> deleteBookWithMediaCleanup({
  required DataStore dataStore,
  required MediaUploadQueue mediaUploadQueue,
  required String bookId,
  required DeleteBookFile deleteBookFile,
}) async {
  await mediaUploadQueue.removeTasksForBook(bookId);
  try {
    await deleteBookFile(bookId);
  } catch (_) {
    // Local cache cleanup is best-effort; the synced book deletion remains authoritative.
  }
  dataStore.deleteBook(bookId);
}
