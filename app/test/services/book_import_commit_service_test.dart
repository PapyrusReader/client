import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_commit_service.dart';
import 'package:papyrus/services/book_import_result.dart';

void main() {
  final addedAt = DateTime.utc(2026, 7, 11, 12, 30);
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

  test('account import persists cover before metadata and enqueues metadata-only uploads in order', () async {
    final calls = <String>[];
    Book? addedBook;
    final service = BookImportCommitService(
      storePendingCover: (actualScope, bookId, bytes) async {
        expect(actualScope, scope);
        expect(bookId, 'book-1');
        expect(bytes, Uint8List.fromList([1, 2, 3]));
        calls.add('store pending cover');
      },
      storeGuestCover: (_, _) async => fail('guest cover must not be stored for an account'),
      addBook: (book) {
        addedBook = book;
        calls.add('add book');
      },
      enqueueBookFile: ({required book, required filename, required contentType}) async {
        expect(book, same(addedBook));
        expect(filename, 'original.epub');
        expect(contentType, 'application/epub+zip');
        calls.add('enqueue book file');
      },
      enqueueCover: ({required book, required filename, required contentType}) async {
        expect(book, same(addedBook));
        expect(filename, 'book-1-cover.png');
        expect(contentType, 'image/png');
        calls.add('enqueue cover');
      },
    );

    final book = await service.commit(
      result: _result(coverImage: Uint8List.fromList([1, 2, 3]), coverMimeType: 'image/png'),
      sourceFilename: 'original.epub',
      addedAt: addedAt,
      localFilePath: 'opfs://books/book-1.epub',
      accountScope: scope,
    );

    expect(calls, ['store pending cover', 'add book', 'enqueue book file', 'enqueue cover']);
    expect(book.coverUrl, isNull);
    expect(book.coverMediaId, isNull);
    expect(jsonEncode(book.toJson()), isNot(contains('data:image')));
    expect(book.toJson()['cover_image_url'], isNull);
    expect(book.toJson()['cover_media_id'], isNull);
    expect(book.id, 'book-1');
    expect(book.title, 'Imported title');
    expect(book.subtitle, 'Imported subtitle');
    expect(book.author, 'Primary author');
    expect(book.coAuthors, ['Second author']);
    expect(book.publisher, 'Publisher');
    expect(book.description, 'Description');
    expect(book.language, 'lt');
    expect(book.isbn, 'isbn-10');
    expect(book.isbn13, 'isbn-13');
    expect(book.pageCount, 321);
    expect(book.filePath, 'opfs://books/book-1.epub');
    expect(book.fileFormat, BookFormat.epub);
    expect(book.fileSize, 1234);
    expect(book.fileHash, 'abc123');
    expect(book.addedAt, addedAt);
  });

  test('guest import stores permanent cover before adding and never enqueues media', () async {
    final calls = <String>[];
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => fail('pending cover must not be stored for a guest'),
      storeGuestCover: (bookId, bytes) async {
        expect(bookId, 'book-1');
        expect(bytes, Uint8List.fromList([4, 5]));
        calls.add('store guest cover');
      },
      addBook: (book) => calls.add('add book'),
      enqueueBookFile: ({required book, required filename, required contentType}) async {
        fail('guest book file must not be enqueued');
      },
      enqueueCover: ({required book, required filename, required contentType}) async {
        fail('guest cover must not be enqueued');
      },
    );

    final book = await service.commit(
      result: _result(coverImage: Uint8List.fromList([4, 5])),
      sourceFilename: 'original.epub',
      addedAt: addedAt,
      localFilePath: 'book-1',
    );

    expect(calls, ['store guest cover', 'add book']);
    expect(book.coverUrl, isNull);
    expect(book.filePath, 'book-1');
  });

  test('no-cover import skips cover work and follows account book-file ordering', () async {
    final calls = <String>[];
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => fail('cover storage must be skipped'),
      storeGuestCover: (_, _) async => fail('cover storage must be skipped'),
      addBook: (_) => calls.add('add book'),
      enqueueBookFile: ({required book, required filename, required contentType}) async {
        calls.add('enqueue book file');
      },
      enqueueCover: ({required book, required filename, required contentType}) async {
        fail('cover enqueue must be skipped');
      },
    );

    await service.commit(
      result: _result(),
      sourceFilename: 'original.epub',
      addedAt: addedAt,
      localFilePath: 'book-1',
      accountScope: scope,
    );

    expect(calls, ['add book', 'enqueue book file']);
  });

  test('cover persistence failure aborts metadata and queue operations', () async {
    final failure = StateError('disk full');
    var added = false;
    var enqueued = false;
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => throw failure,
      storeGuestCover: (_, _) async => throw failure,
      addBook: (_) => added = true,
      enqueueBookFile: ({required book, required filename, required contentType}) async {
        enqueued = true;
      },
      enqueueCover: ({required book, required filename, required contentType}) async {
        enqueued = true;
      },
    );

    await expectLater(
      service.commit(
        result: _result(coverImage: Uint8List.fromList([9])),
        sourceFilename: 'original.epub',
        addedAt: addedAt,
        localFilePath: 'book-1',
        accountScope: scope,
      ),
      throwsA(same(failure)),
    );
    expect(added, isFalse);
    expect(enqueued, isFalse);
  });
}

BookImportResult _result({Uint8List? coverImage, String? coverMimeType}) {
  return BookImportResult(
    bookId: 'book-1',
    title: 'Imported title',
    subtitle: 'Imported subtitle',
    author: 'Primary author',
    coAuthors: const ['Second author'],
    publisher: 'Publisher',
    description: 'Description',
    language: 'lt',
    isbn: 'isbn-10',
    isbn13: 'isbn-13',
    pageCount: 321,
    coverImage: coverImage,
    coverMimeType: coverMimeType,
    fileSize: 1234,
    fileHash: 'abc123',
    fileExtension: 'epub',
  );
}
