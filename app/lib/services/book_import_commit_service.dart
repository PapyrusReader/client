import 'dart:async';
import 'dart:typed_data';

import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_result.dart';

typedef PendingCoverStore = Future<void> Function(MediaStorageScope scope, String bookId, Uint8List bytes);
typedef GuestCoverStore = Future<void> Function(String bookId, Uint8List bytes);
typedef PendingCoverDelete = FutureOr<void> Function(MediaStorageScope scope, String bookId);
typedef GuestCoverDelete = FutureOr<void> Function(String bookId);
typedef BookAdder = FutureOr<void> Function(Book book);
typedef BookDelete = FutureOr<void> Function(String bookId);
typedef LibraryContextValidator = bool Function();
typedef ImportedBookMediaEnqueuer =
    Future<void> Function({
      required MediaStorageScope scope,
      required Book book,
      required String filename,
      required String contentType,
      String? coverFilename,
      String? coverContentType,
    });

/// Commits an imported book and its local media in a safe, deterministic order.
class BookImportCommitService {
  const BookImportCommitService({
    required PendingCoverStore storePendingCover,
    required GuestCoverStore storeGuestCover,
    required PendingCoverDelete deletePendingCover,
    required GuestCoverDelete deleteGuestCover,
    required BookAdder addBook,
    required BookDelete deleteBook,
    required ImportedBookMediaEnqueuer enqueueImportedBookMedia,
    LibraryContextValidator isLibraryContextCurrent = _alwaysCurrent,
  }) : _storePendingCover = storePendingCover,
       _storeGuestCover = storeGuestCover,
       _deletePendingCover = deletePendingCover,
       _deleteGuestCover = deleteGuestCover,
       _addBook = addBook,
       _deleteBook = deleteBook,
       _enqueueImportedBookMedia = enqueueImportedBookMedia,
       _isLibraryContextCurrent = isLibraryContextCurrent;

  final PendingCoverStore _storePendingCover;
  final GuestCoverStore _storeGuestCover;
  final PendingCoverDelete _deletePendingCover;
  final GuestCoverDelete _deleteGuestCover;
  final BookAdder _addBook;
  final BookDelete _deleteBook;
  final ImportedBookMediaEnqueuer _enqueueImportedBookMedia;
  final LibraryContextValidator _isLibraryContextCurrent;

  Future<Book> commit({
    required BookImportResult result,
    required String sourceFilename,
    required DateTime addedAt,
    required String localFilePath,
    MediaStorageScope? accountScope,
  }) async {
    final book = Book(
      id: result.bookId,
      title: result.title,
      subtitle: result.subtitle,
      author: result.author,
      coAuthors: result.coAuthors,
      publisher: result.publisher,
      description: result.description,
      language: result.language,
      isbn: result.isbn,
      isbn13: result.isbn13,
      pageCount: result.pageCount,
      coverUrl: null,
      coverMediaId: null,
      filePath: localFilePath,
      fileFormat: _bookFormat(result.fileExtension),
      fileSize: result.fileSize,
      fileHash: result.fileHash,
      addedAt: addedAt,
    );

    final coverImage = result.coverImage;
    var coverStored = false;
    var metadataAdded = false;
    try {
      if (coverImage != null) {
        if (accountScope != null) {
          await _storePendingCover(accountScope, book.id, coverImage);
        } else {
          await _storeGuestCover(book.id, coverImage);
        }
        coverStored = true;
      }

      _ensureLibraryContextCurrent();

      await _addBook(book);
      metadataAdded = true;
      _ensureLibraryContextCurrent();

      if (accountScope != null) {
        await _enqueueImportedBookMedia(
          scope: accountScope,
          book: book,
          filename: sourceFilename,
          contentType: _bookContentType(result.fileExtension),
          coverFilename: coverImage == null ? null : '${book.id}-cover.${_coverExtension(result.coverMimeType)}',
          coverContentType: coverImage == null ? null : result.coverMimeType ?? 'image/jpeg',
        );
      }

      return book;
    } catch (error, stackTrace) {
      if (metadataAdded) {
        await _bestEffort(() => _deleteBook(book.id));
      }
      if (coverStored) {
        if (accountScope != null) {
          await _bestEffort(() => _deletePendingCover(accountScope, book.id));
        } else {
          await _bestEffort(() => _deleteGuestCover(book.id));
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _ensureLibraryContextCurrent() {
    if (!_isLibraryContextCurrent()) {
      throw StateError('Library context changed during book import');
    }
  }
}

bool _alwaysCurrent() => true;

Future<void> _bestEffort(FutureOr<void> Function() compensation) async {
  try {
    await compensation();
  } catch (_) {
    // Preserve the import failure; compensation is intentionally best effort.
  }
}

BookFormat? _bookFormat(String extension) {
  for (final format in BookFormat.values) {
    if (format.name == extension) return format;
  }
  return null;
}

String _bookContentType(String extension) {
  return switch (extension) {
    'epub' => 'application/epub+zip',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'cbz' => 'application/vnd.comicbook+zip',
    'cbr' => 'application/vnd.comicbook-rar',
    _ => 'application/octet-stream',
  };
}

String _coverExtension(String? contentType) {
  return switch (contentType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };
}
