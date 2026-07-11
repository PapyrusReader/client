import 'dart:typed_data';

import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_result.dart';

typedef PendingCoverStore = Future<void> Function(MediaStorageScope scope, String bookId, Uint8List bytes);
typedef GuestCoverStore = Future<void> Function(String bookId, Uint8List bytes);
typedef BookAdder = void Function(Book book);
typedef MediaEnqueuer =
    Future<void> Function({required Book book, required String filename, required String contentType});

/// Commits an imported book and its local media in a safe, deterministic order.
class BookImportCommitService {
  const BookImportCommitService({
    required PendingCoverStore storePendingCover,
    required GuestCoverStore storeGuestCover,
    required BookAdder addBook,
    required MediaEnqueuer enqueueBookFile,
    required MediaEnqueuer enqueueCover,
  }) : _storePendingCover = storePendingCover,
       _storeGuestCover = storeGuestCover,
       _addBook = addBook,
       _enqueueBookFile = enqueueBookFile,
       _enqueueCover = enqueueCover;

  final PendingCoverStore _storePendingCover;
  final GuestCoverStore _storeGuestCover;
  final BookAdder _addBook;
  final MediaEnqueuer _enqueueBookFile;
  final MediaEnqueuer _enqueueCover;

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
    if (coverImage != null) {
      if (accountScope != null) {
        await _storePendingCover(accountScope, book.id, coverImage);
      } else {
        await _storeGuestCover(book.id, coverImage);
      }
    }

    _addBook(book);

    if (accountScope != null) {
      await _enqueueBookFile(book: book, filename: sourceFilename, contentType: _bookContentType(result.fileExtension));
      if (coverImage != null) {
        await _enqueueCover(
          book: book,
          filename: '${book.id}-cover.${_coverExtension(result.coverMimeType)}',
          contentType: result.coverMimeType ?? 'image/jpeg',
        );
      }
    }

    return book;
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
