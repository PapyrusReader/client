import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';

typedef DeleteBookFile = Future<void> Function(String bookId);
typedef DeleteCoverFile = Future<void> Function(String mediaId);

Future<void> deleteBookWithMediaCleanup({
  required DataStore dataStore,
  required MediaUploadQueue mediaUploadQueue,
  required String bookId,
  required DeleteBookFile deleteBookFile,
  String? coverMediaId,
  DeleteCoverFile? deleteCoverFile,
}) async {
  await mediaUploadQueue.removeTasksForBook(bookId);
  try {
    await deleteBookFile(bookId);
  } catch (_) {
    // Local cache cleanup is best-effort; the synced book deletion remains authoritative.
  }
  if (coverMediaId != null && deleteCoverFile != null) {
    try {
      await deleteCoverFile(coverMediaId);
    } catch (_) {
      // A missing or inaccessible local cover must not block book deletion.
    }
  }
  dataStore.deleteBook(bookId);
}
