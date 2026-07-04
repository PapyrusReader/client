import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('processPending uploads book file and stores returned media id on the book', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await repository.upsert(book);
    await pumpEventQueue();
    final queue = MediaUploadQueue(prefs);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await queue.processPending(
      dataStore: dataStore,
      readBookFile: (bookId) async => Uint8List.fromList('epub bytes'.codeUnits),
      uploadMedia: (payload) async {
        expect(payload.bookId, book.id);
        expect(payload.kind, MediaKind.bookFile);
        expect(payload.bytes, Uint8List.fromList('epub bytes'.codeUnits));
        return _asset(assetId: 'file-asset', bookId: book.id, kind: MediaKind.bookFile);
      },
    );

    expect(queue.pendingTasks, isEmpty);
    expect(dataStore.getBook(book.id)?.fileMediaId, 'file-asset');
  });

  test('processPending keeps quota failures visible without dropping local media', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await repository.upsert(book);
    await pumpEventQueue();
    final queue = MediaUploadQueue(prefs);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await queue.processPending(
      dataStore: dataStore,
      readBookFile: (bookId) async => Uint8List.fromList('epub bytes'.codeUnits),
      uploadMedia: (payload) async => throw const MediaUploadException.storageFull(),
    );

    expect(queue.pendingTasks, hasLength(1));
    expect(queue.pendingTasks.single.status, MediaUploadTaskStatus.failed);
    expect(queue.pendingTasks.single.errorMessage, 'Storage full');
    expect(dataStore.getBook(book.id)?.fileMediaId, isNull);
    expect(dataStore.getBook(book.id)?.filePath, 'book-1');
  });

  test('retryFailed returns failed upload tasks to pending', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await repository.upsert(book);
    await pumpEventQueue();
    final queue = MediaUploadQueue(prefs);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await queue.processPending(
      dataStore: dataStore,
      readBookFile: (bookId) async => Uint8List.fromList('epub bytes'.codeUnits),
      uploadMedia: (payload) async => throw const MediaUploadException.storageFull(),
    );

    await queue.retryFailed();

    expect(queue.pendingTasks.single.status, MediaUploadTaskStatus.pending);
    expect(queue.pendingTasks.single.errorMessage, isNull);
  });

  test('removeTasksForBook removes queued book file and cover uploads', () async {
    final prefs = await SharedPreferences.getInstance();
    final queue = MediaUploadQueue(prefs);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');

    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');
    await queue.enqueueCover(
      book: book,
      filename: 'cover.jpg',
      contentType: 'image/jpeg',
      bytes: Uint8List.fromList('cover'.codeUnits),
    );

    await queue.removeTasksForBook(book.id);

    expect(queue.pendingTasks, isEmpty);
    expect(prefs.getString('media_upload_queue'), '[]');
  });
}

Book _book({String? filePath, int? fileSize, String? fileHash}) {
  return Book(
    id: '11111111-1111-1111-1111-111111111111',
    title: 'Book',
    author: 'Author',
    filePath: filePath,
    fileSize: fileSize,
    fileHash: fileHash,
    fileFormat: BookFormat.epub,
    addedAt: DateTime.utc(2026, 6, 27),
  );
}

MediaAsset _asset({required String assetId, required String bookId, required MediaKind kind}) {
  return MediaAsset(
    assetId: assetId,
    ownerUserId: 'user-id',
    bookId: bookId,
    kind: kind,
    originalFilename: 'book.epub',
    contentType: 'application/epub+zip',
    extension: 'epub',
    sizeBytes: 10,
    sha256: 'hash',
    storagePath: 'path',
  );
}
