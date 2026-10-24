import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';

class GuestAccountDeletionService {
  const GuestAccountDeletionService({
    required this.auth,
    required this.library,
    required this.files,
    required this.catalogs,
    required this.downloads,
  });

  final AuthProvider auth;
  final PapyrusPowerSyncService library;
  final BookImportService files;
  final OpdsCatalogs catalogs;
  final OpdsDownloads downloads;

  Future<void> delete() => auth.deleteGuestAccount(() async {
    await downloads.cancelAndWait();

    await library.deleteGuestLibrary(
      deleteFiles: (books) async {
        for (final book in books) {
          await files.deleteBookFile(book.id);
        }

        await files.clearCoverFiles(MediaStorageScope.localGuest);
        await catalogs.clearScope(MediaStorageScope.localGuest.persistenceKey);
      },
    );
  });
}
