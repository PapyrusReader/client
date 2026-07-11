import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_commit_service.dart';
import 'package:papyrus/services/book_import_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final addedAt = DateTime.utc(2026, 7, 11, 12, 30);
  final accountScope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('account import persists cover before metadata and enqueues metadata-only uploads in order', () async {
    final calls = <String>[];
    Book? addedBook;
    final service = BookImportCommitService(
      storePendingCover: (actualScope, bookId, bytes) async {
        expect(actualScope, accountScope);
        expect(bookId, 'book-1');
        expect(bytes, Uint8List.fromList([1, 2, 3]));
        calls.add('store pending cover');
      },
      storeGuestCover: (_, _) async => fail('guest cover must not be stored for an account'),
      deletePendingCover: (_, _) async => fail('compensation must not run'),
      deleteGuestCover: (_) async => fail('compensation must not run'),
      addBook: (book) {
        addedBook = book;
        calls.add('add book');
      },
      deleteBook: (_) => fail('compensation must not run'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            expect(scope, accountScope);
            expect(book, same(addedBook));
            expect(filename, 'original.epub');
            expect(contentType, 'application/epub+zip');
            expect(coverFilename, 'book-1-cover.png');
            expect(coverContentType, 'image/png');
            calls.add('enqueue imported media');
          },
    );

    final book = await service.commit(
      result: _result(coverImage: Uint8List.fromList([1, 2, 3]), coverMimeType: 'image/png'),
      sourceFilename: 'original.epub',
      addedAt: addedAt,
      localFilePath: 'opfs://books/book-1.epub',
      accountScope: accountScope,
    );

    expect(calls, ['store pending cover', 'add book', 'enqueue imported media']);
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
      deletePendingCover: (_, _) async => fail('compensation must not run'),
      deleteGuestCover: (_) async => fail('compensation must not run'),
      addBook: (book) => calls.add('add book'),
      deleteBook: (_) => fail('compensation must not run'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            fail('guest media must not be enqueued');
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
      deletePendingCover: (_, _) async => fail('compensation must not run'),
      deleteGuestCover: (_) async => fail('compensation must not run'),
      addBook: (_) => calls.add('add book'),
      deleteBook: (_) => fail('compensation must not run'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            expect(scope, accountScope);
            expect(coverFilename, isNull);
            expect(coverContentType, isNull);
            calls.add('enqueue imported media');
          },
    );

    await service.commit(
      result: _result(),
      sourceFilename: 'original.epub',
      addedAt: addedAt,
      localFilePath: 'book-1',
      accountScope: accountScope,
    );

    expect(calls, ['add book', 'enqueue imported media']);
  });

  test('cover persistence failure aborts metadata and queue operations', () async {
    final failure = StateError('disk full');
    var added = false;
    var enqueued = false;
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => throw failure,
      storeGuestCover: (_, _) async => throw failure,
      deletePendingCover: (_, _) async => fail('unstored cover must not be deleted'),
      deleteGuestCover: (_) async => fail('unstored cover must not be deleted'),
      addBook: (_) => added = true,
      deleteBook: (_) => fail('unadded book must not be deleted'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            enqueued = true;
          },
    );

    await expectLater(
      service.commit(
        result: _result(coverImage: Uint8List.fromList([9])),
        sourceFilename: 'original.epub',
        addedAt: addedAt,
        localFilePath: 'book-1',
        accountScope: accountScope,
      ),
      throwsA(same(failure)),
    );
    expect(added, isFalse);
    expect(enqueued, isFalse);
  });

  test('account add failure deletes the stored pending cover and preserves the original error', () async {
    final failure = StateError('add failed');
    final calls = <String>[];
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => calls.add('store pending cover'),
      storeGuestCover: (_, _) async => fail('guest cover must not be stored'),
      deletePendingCover: (_, _) async {
        calls.add('delete pending cover');
        throw StateError('cleanup failed');
      },
      deleteGuestCover: (_) async => fail('guest cover must not be deleted'),
      addBook: (_) {
        calls.add('add book');
        throw failure;
      },
      deleteBook: (_) => fail('failed add must not delete metadata'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            fail('media must not be enqueued');
          },
    );

    await expectLater(
      service.commit(
        result: _result(coverImage: Uint8List.fromList([1])),
        sourceFilename: 'original.epub',
        addedAt: addedAt,
        localFilePath: 'book-1',
        accountScope: accountScope,
      ),
      throwsA(same(failure)),
    );
    expect(calls, ['store pending cover', 'add book', 'delete pending cover']);
  });

  test('guest add failure deletes the stored guest cover', () async {
    final failure = StateError('add failed');
    final calls = <String>[];
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => fail('pending cover must not be stored'),
      storeGuestCover: (_, _) async => calls.add('store guest cover'),
      deletePendingCover: (_, _) async => fail('pending cover must not be deleted'),
      deleteGuestCover: (_) async => calls.add('delete guest cover'),
      addBook: (_) {
        calls.add('add book');
        throw failure;
      },
      deleteBook: (_) => fail('failed add must not delete metadata'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            fail('guest media must not be enqueued');
          },
    );

    await expectLater(
      service.commit(
        result: _result(coverImage: Uint8List.fromList([1])),
        sourceFilename: 'original.epub',
        addedAt: addedAt,
        localFilePath: 'book-1',
      ),
      throwsA(same(failure)),
    );
    expect(calls, ['store guest cover', 'add book', 'delete guest cover']);
  });

  test('batch failure deletes metadata and pending cover in order without leaving a task', () async {
    final calls = <String>[];
    final prefs = await SharedPreferences.getInstance();
    final switchedScope = MediaStorageScope(profileKey: 'official', userId: 'user-2');
    final queue = MediaUploadQueue(prefs);
    await queue.activateScope(accountScope);
    await queue.activateScope(switchedScope);
    final service = BookImportCommitService(
      storePendingCover: (_, _, _) async => calls.add('store pending cover'),
      storeGuestCover: (_, _) async => fail('guest cover must not be stored'),
      deletePendingCover: (_, _) async => calls.add('delete pending cover'),
      deleteGuestCover: (_) async => fail('guest cover must not be deleted'),
      addBook: (_) => calls.add('add book'),
      deleteBook: (_) => calls.add('delete book'),
      enqueueImportedBookMedia:
          ({
            required scope,
            required book,
            required filename,
            required contentType,
            coverFilename,
            coverContentType,
          }) async {
            calls.add('enqueue imported media');
            await queue.enqueueImportedBookMedia(
              scope: scope,
              book: book,
              filename: filename,
              contentType: contentType,
              coverFilename: coverFilename,
              coverContentType: coverContentType,
            );
          },
    );

    await expectLater(
      service.commit(
        result: _result(coverImage: Uint8List.fromList([1])),
        sourceFilename: 'original.epub',
        addedAt: addedAt,
        localFilePath: 'book-1',
        accountScope: accountScope,
      ),
      throwsStateError,
    );
    expect(calls, ['store pending cover', 'add book', 'enqueue imported media', 'delete book', 'delete pending cover']);
    expect(queue.pendingTasks, isEmpty);
    expect(prefs.getString('media_upload_queue:${accountScope.persistenceKey}'), isNull);
    expect(prefs.getString('media_upload_queue:${switchedScope.persistenceKey}'), isNull);
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
