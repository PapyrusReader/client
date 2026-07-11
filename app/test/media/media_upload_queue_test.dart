import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';
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
    final queue = await _activeQueue(prefs);
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
    final queue = await _activeQueue(prefs);
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
    final queue = await _activeQueue(prefs);
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
    final queue = await _activeQueue(prefs);
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
    expect(prefs.getString('media_upload_queue:official--user-1'), '[]');
  });

  test('pending uploads are isolated and restored per media scope', () async {
    final prefs = await SharedPreferences.getInstance();
    final queue = MediaUploadQueue(prefs);
    final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final second = MediaStorageScope(profileKey: 'custom-a', userId: 'user-2');
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');

    await queue.activateScope(first);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');
    await queue.activateScope(second);
    expect(queue.pendingTasks, isEmpty);

    await queue.activateScope(first);
    expect(queue.pendingTasks, hasLength(1));
    expect(queue.pendingTasks.single.bookId, book.id);
  });

  test('signed out queue exposes no authenticated tasks', () async {
    final prefs = await SharedPreferences.getInstance();
    final queue = MediaUploadQueue(prefs);
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await queue.activateScope(scope);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    await queue.activateScope(null);

    expect(queue.activeScope, isNull);
    expect(queue.pendingTasks, isEmpty);
  });

  test('overlapping processPending calls share one upload operation', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await repository.upsert(book);
    await pumpEventQueue();
    final queue = MediaUploadQueue(prefs);
    await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');
    final gate = Completer<MediaAsset>();
    var uploads = 0;

    Future<void> process() {
      return queue.processPending(
        dataStore: dataStore,
        readBookFile: (_) async => Uint8List.fromList([1, 2, 3]),
        uploadMedia: (_) {
          uploads++;
          return gate.future;
        },
      );
    }

    final first = process();
    final second = process();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(uploads, 1);

    gate.complete(_asset(assetId: 'file-asset', bookId: book.id, kind: MediaKind.bookFile));
    await Future.wait([first, second]);
    expect(uploads, 1);
  });

  test('enqueue during an upload is persisted and drained before processing completes', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final firstBook = _book(id: '11111111-1111-1111-1111-111111111111', filePath: 'book-1');
    final secondBook = _book(id: '22222222-2222-2222-2222-222222222222', filePath: 'book-2');
    await repository.upsert(firstBook);
    await repository.upsert(secondBook);
    await pumpEventQueue();
    final firstUploadStarted = Completer<void>();
    final releaseFirstUpload = Completer<void>();
    final uploadedBookIds = <String>[];
    late MediaUploadQueue queue;

    Future<void> process() => queue.processPending(
      dataStore: dataStore,
      readBookFile: (_) async => Uint8List.fromList([1]),
      uploadMedia: (payload) async {
        uploadedBookIds.add(payload.bookId);
        if (payload.bookId == firstBook.id) {
          firstUploadStarted.complete();
          await releaseFirstUpload.future;
        }
        return _asset(assetId: 'asset-${payload.bookId}', bookId: payload.bookId, kind: payload.kind);
      },
    );

    queue = MediaUploadQueue(prefs, onWorkAvailable: process);
    await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
    final firstEnqueue = queue.enqueueBookFile(
      book: firstBook,
      filename: 'first.epub',
      contentType: 'application/epub+zip',
    );
    await firstUploadStarted.future;
    final secondEnqueue = queue.enqueueBookFile(
      book: secondBook,
      filename: 'second.epub',
      contentType: 'application/epub+zip',
    );
    await pumpEventQueue();
    releaseFirstUpload.complete();

    await Future.wait([firstEnqueue, secondEnqueue]);

    expect(uploadedBookIds, [firstBook.id, secondBook.id]);
    expect(queue.pendingTasks, isEmpty);
    expect(prefs.getString('media_upload_queue:official--user-1'), '[]');
  });

  test('removing a book during a failed upload does not resurrect its task', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1');
    await repository.upsert(book);
    await pumpEventQueue();
    final uploadStarted = Completer<void>();
    final releaseUpload = Completer<void>();
    final queue = await _activeQueue(prefs);
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');

    final processing = queue.processPending(
      dataStore: dataStore,
      readBookFile: (_) async => Uint8List.fromList([1]),
      uploadMedia: (_) async {
        uploadStarted.complete();
        await releaseUpload.future;
        throw const MediaUploadException('network failure');
      },
    );
    await uploadStarted.future;
    await queue.removeTasksForBook(book.id);
    releaseUpload.complete();
    await processing;

    expect(queue.pendingTasks, isEmpty);
    expect(prefs.getString('media_upload_queue:official--user-1'), '[]');
  });

  test('enqueue invokes work callback after scoped tasks are persisted', () async {
    final prefs = await SharedPreferences.getInstance();
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    String? storedAtCallback;
    final queue = MediaUploadQueue(
      prefs,
      onWorkAvailable: () async {
        storedAtCallback = prefs.getString('media_upload_queue:${scope.persistenceKey}');
      },
    );
    await queue.activateScope(scope);

    await queue.enqueueBookFile(
      book: _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash'),
      filename: 'book.epub',
      contentType: 'application/epub+zip',
    );

    expect(storedAtCallback, isNotNull);
    expect(jsonDecode(storedAtCallback!) as List<dynamic>, hasLength(1));
  });

  test('retry invokes work callback only when failed tasks become pending', () async {
    final prefs = await SharedPreferences.getInstance();
    var callbacks = 0;
    final queue = MediaUploadQueue(prefs, onWorkAvailable: () async => callbacks++);
    await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final book = _book(filePath: 'book-1', fileSize: 10, fileHash: 'hash');
    await repository.upsert(book);
    await pumpEventQueue();
    await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');
    callbacks = 0;
    await queue.processPending(
      dataStore: dataStore,
      readBookFile: (_) async => Uint8List.fromList([1]),
      uploadMedia: (_) async => throw const MediaUploadException.storageFull(),
    );

    await queue.retryFailed();
    await queue.retryFailed();

    expect(callbacks, 1);
  });
}

Book _book({String id = '11111111-1111-1111-1111-111111111111', String? filePath, int? fileSize, String? fileHash}) {
  return Book(
    id: id,
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

Future<MediaUploadQueue> _activeQueue(SharedPreferences prefs) async {
  final queue = MediaUploadQueue(prefs);
  await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: 'user-1'));
  return queue;
}
