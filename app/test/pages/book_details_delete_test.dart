import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/services/book_download_service.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('details overflow delete removes the book and pending media uploads', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final mediaUploadQueue = MediaUploadQueue(prefs);
    final importService = _RecordingBookImportService();
    final book = Book(id: 'book-1', title: 'Delete Me', author: 'Author', addedAt: DateTime.utc(2026));

    await repository.upsert(book);
    await tester.pump();
    await mediaUploadQueue.enqueueBookFile(book: book, filename: 'delete-me.epub', contentType: 'application/epub+zip');

    final router = GoRouter(
      initialLocation: '/library/books/${book.id}',
      routes: [
        GoRoute(
          path: '/library/books',
          builder: (context, state) => const Scaffold(body: Text('Library books')),
        ),
        GoRoute(
          path: '/library/books/:bookId',
          builder: (context, state) => BookDetailsPage(id: state.pathParameters['bookId']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataStore>.value(value: dataStore),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: mediaUploadQueue),
          Provider<BookImportService>.value(value: importService),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete book?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(importService.deletedBookIds, [book.id]);
    expect(mediaUploadQueue.pendingTasks, isEmpty);
    expect(await repository.getById(book.id), isNull);
    expect(find.text('Library books'), findsOneWidget);
  });

  testWidgets('details overflow menu shows download before delete', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final mediaUploadQueue = MediaUploadQueue(prefs);
    final importService = _RecordingBookImportService();
    final book = Book(id: 'book-1', title: 'Download Me', author: 'Author', addedAt: DateTime.utc(2026));

    await repository.upsert(book);
    await tester.pump();

    final router = GoRouter(
      initialLocation: '/library/books/${book.id}',
      routes: [
        GoRoute(
          path: '/library/books',
          builder: (context, state) => const Scaffold(body: Text('Library books')),
        ),
        GoRoute(
          path: '/library/books/:bookId',
          builder: (context, state) => BookDetailsPage(id: state.pathParameters['bookId']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataStore>.value(value: dataStore),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: mediaUploadQueue),
          Provider<BookImportService>.value(value: importService),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final downloadTop = tester.getTopLeft(find.text('Download')).dy;
    final deleteTop = tester.getTopLeft(find.text('Delete')).dy;

    expect(downloadTop, lessThan(deleteTop));
  });

  testWidgets('details overflow download saves the cached book file', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = InMemoryBookRepository();
    final dataStore = DataStore(bookRepository: repository);
    final mediaUploadQueue = MediaUploadQueue(prefs);
    final importService = _RecordingBookImportService();
    final downloadService = _RecordingBookDownloadService();
    final bytes = Uint8List.fromList('cached epub bytes'.codeUnits);
    final book = Book(
      id: 'book-1',
      title: 'Download Me',
      author: 'Author',
      fileFormat: BookFormat.epub,
      fileHash: const MediaCacheService().sha256Hex(bytes),
      addedAt: DateTime.utc(2026),
    );

    importService.bookFiles[book.id] = bytes;
    await repository.upsert(book);
    await tester.pump();

    final router = GoRouter(
      initialLocation: '/library/books/${book.id}',
      routes: [
        GoRoute(
          path: '/library/books',
          builder: (context, state) => const Scaffold(body: Text('Library books')),
        ),
        GoRoute(
          path: '/library/books/:bookId',
          builder: (context, state) => BookDetailsPage(id: state.pathParameters['bookId']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataStore>.value(value: dataStore),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: mediaUploadQueue),
          Provider<BookImportService>.value(value: importService),
          Provider<MediaCacheService>.value(value: const MediaCacheService()),
          Provider<BookDownloadService>.value(value: downloadService),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(downloadService.savedBooks, [book.id]);
    expect(downloadService.savedBytes, bytes);
    expect(find.text('Downloaded "Download Me"'), findsOneWidget);
  });
}

class _RecordingBookImportService extends BookImportService {
  final List<String> deletedBookIds = [];
  final Map<String, Uint8List> bookFiles = {};

  @override
  Future<void> deleteBookFile(String bookId) async {
    deletedBookIds.add(bookId);
  }

  @override
  Future<Uint8List?> getBookFile(String bookId) async {
    return bookFiles[bookId];
  }

  @override
  Future<void> storeBookFile(String bookId, String extension, Uint8List bytes) async {
    bookFiles[bookId] = bytes;
  }
}

class _RecordingBookDownloadService extends BookDownloadService {
  final List<String> savedBooks = [];
  Uint8List? savedBytes;

  @override
  Future<BookDownloadResult> saveBookFile({required Book book, required Uint8List bytes}) async {
    savedBooks.add(book.id);
    savedBytes = bytes;
    return const BookDownloadResult.saved('/downloads/download-me.epub');
  }
}
