import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';

typedef DeleteBookFile = Future<void> Function(String bookId);
typedef DeleteBookCover = Future<void> Function(String bookId);
typedef DeleteCoverFile = Future<void> Function(String mediaId);

Future<void> deleteBookWithMediaCleanup({
  required DataStore dataStore,
  required MediaUploadQueue mediaUploadQueue,
  required String bookId,
  required DeleteBookFile deleteBookFile,
  String? coverMediaId,
  DeleteBookCover? deletePendingCover,
  DeleteBookCover? deleteGuestCover,
  DeleteCoverFile? deleteCoverFile,
}) async {
  await mediaUploadQueue.removeTasksForBook(bookId);
  await _bestEffort(() => deleteBookFile(bookId));
  if (deletePendingCover != null) {
    await _bestEffort(() => deletePendingCover(bookId));
  }
  if (deleteGuestCover != null) {
    await _bestEffort(() => deleteGuestCover(bookId));
  }
  if (coverMediaId != null && deleteCoverFile != null) {
    await _bestEffort(() => deleteCoverFile(coverMediaId));
  }
  dataStore.deleteBook(bookId);
}

Future<void> _bestEffort(Future<void> Function() cleanup) async {
  try {
    await cleanup();
  } catch (_) {
    // Local cleanup must not block the authoritative metadata deletion.
  }
}
