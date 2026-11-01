import 'dart:typed_data';

import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_session.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';

/// A captured library destination, also used to recover a partially committed job.
abstract interface class FolderImportTarget {
  bool get isCurrent;
  List<Book> get books;
  Future<Book?> getBook(String id);
  Future<Uint8List?> readStored(String id);
  Future<BookImportResult> process(Uint8List bytes, String filename, String id);
  Future<void> finish(BookImportResult result, String filename, String? shelfId);
  Future<void> ensureCopy(Book book, Uint8List bytes, String extension, String? shelfId);
  Future<void> deleteStaged(String id);
}

class LibraryFolderImportTarget implements FolderImportTarget {
  LibraryFolderImportTarget({
    required this.store,
    required this.queue,
    required this.importer,
    required AuthProvider auth,
    required PapyrusPowerSyncService database,
  }) : session = BookImportSession.capture(
         dataStore: store,
         queue: queue,
         importService: importer,
         authProvider: auth,
         powerSyncService: database,
         retainCommittedBook: true,
       ),
       repository = store.requireBookRepository(),
       shelves = store.libraryRepository?.shelves,
       memberships = store.libraryRepository?.bookShelves,
       scope = queue.activeScope;

  final DataStore store;
  final MediaUploadQueue queue;
  final BookImportService importer;
  final BookImportSession session;
  final BookRepository repository;
  final EntityRepository<Shelf>? shelves;
  final EntityRepository<BookShelfRelation>? memberships;
  final MediaStorageScope? scope;

  @override
  bool get isCurrent => session.isCurrent();

  @override
  List<Book> get books => store.books;

  void _check() {
    if (!isCurrent) {
      throw StateError('The selected library changed.');
    }
  }

  @override
  Future<Book?> getBook(String id) async => await repository.getById(id);

  @override
  Future<Uint8List?> readStored(String id) => importer.getBookFile(id);

  @override
  Future<BookImportResult> process(Uint8List bytes, String filename, String id) =>
      importer.importBookWithId(bytes, filename, id);

  @override
  Future<void> finish(BookImportResult result, String filename, String? shelfId) async {
    _check();
    final existing = await getBook(result.bookId);
    _check();

    if (existing == null) {
      await session.commit(result, filename);
    } else if (scope != null) {
      // Metadata may have committed before the media queue persisted. Keep edits
      // and reading positions intact while repairing only the missing outbox work.
      if (existing.fileMediaId == null && !queue.pendingTasks.any((task) => task.id == '${existing.id}:book_file')) {
        await queue.enqueueBookFile(
          book: existing,
          filename: filename,
          contentType: _contentType(result.fileExtension),
        );
      }

      _check();

      if (existing.coverMediaId == null &&
          result.coverImage != null &&
          !queue.pendingTasks.any((task) => task.id == '${existing.id}:cover_image')) {
        await importer.storePendingCoverFile(scope!, existing.id, result.coverImage!);
        _check();
        await queue.enqueueCover(
          book: existing,
          filename: '${existing.id}-cover',
          contentType: result.coverMimeType ?? 'image/jpeg',
        );
      }
    }

    await _shelf(result.bookId, shelfId);
  }

  Future<void> _shelf(String bookId, String? shelfId) async {
    _check();

    if (shelfId == null || memberships == null || await shelves?.getById(shelfId) == null) {
      return;
    }

    _check();
    final relation = BookShelfRelation(bookId: bookId, shelfId: shelfId, addedAt: DateTime.now().toUtc());

    if (await memberships!.getById('$bookId:$shelfId') == null) {
      _check();
      await memberships!.upsert(relation);
    }
  }

  @override
  Future<void> ensureCopy(Book book, Uint8List bytes, String extension, String? shelfId) async {
    _check();

    if (!await importer.hasBookFile(book.id)) {
      _check();
      await importer.storeBookFile(book.id, extension, bytes);
    }

    await _shelf(book.id, shelfId);
  }

  @override
  Future<void> deleteStaged(String id) => importer.deleteBookFile(id);
}

String _contentType(String extension) => switch (extension) {
  'epub' => 'application/epub+zip',
  'pdf' => 'application/pdf',
  'txt' => 'text/plain',
  'cbz' => 'application/vnd.comicbook+zip',
  'cbr' => 'application/vnd.comicbook-rar',
  _ => 'application/octet-stream',
};
