import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:papyrus/pages/reader_page.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final format in [BookFormat.epub, BookFormat.pdf]) {
    testWidgets('explicit $format location takes precedence over resume position', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      final ReaderLocator target = format == BookFormat.epub
          ? EpubReaderLocator(spineIndex: 3, textOffset: 456, localProgression: .25, totalProgression: .4)
          : PdfReaderLocator(pageIndex: 7, pageOffset: .35, totalProgression: .4);
      final ReaderLocator resume = format == BookFormat.epub
          ? EpubReaderLocator(spineIndex: 1, textOffset: 0, localProgression: 0, totalProgression: .1)
          : PdfReaderLocator(pageIndex: 1, pageOffset: 0, totalProgression: .1);
      final book = buildTestBook(
        id: 'location-book',
        fileFormat: format,
        customMetadata: {'reader_locator': resume.toJson()},
      );
      final store = DataStore()..loadData(books: [book]);
      addTearDown(store.dispose);
      final cache = _ReaderMediaCache();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider.value(value: preferences),
            Provider<MediaCacheService>.value(value: cache),
            Provider<BookImportService>(create: (_) => BookImportService()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _ReaderAuth()),
          ],
          child: MaterialApp(
            home: ReaderPage(bookId: book.id, location: jsonEncode(target.toJson())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final reader = tester.widget<PapyrusReader>(find.byType(PapyrusReader));
      expect(reader.initialLocator, target);
      expect(reader.onNote, isNull);
      expect(cache.loads, 1);
      expect(store.getBook(book.id)!.customMetadata!['reader_locator'], resume.toJson());
      final readerContext = tester.element(find.byType(PapyrusReader));

      showDialog<void>(
        context: readerContext,
        builder: (context) => Dialog(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: reader.builders.toolbarActions!(
              context,
              ReaderToolbarContext(
                document: reader.document,
                snapshot: ReaderReadySnapshot(
                  document: reader.document,
                  preferences: const ReaderPreferences(),
                  capabilities: const ReaderCapabilities(),
                  locator: target,
                ),
                openTableOfContents: () {},
                openSettings: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getCenter(find.byTooltip('New note')).dx,
        greaterThan(tester.getCenter(find.byTooltip('Add bookmark')).dx),
      );
      await tester.tap(find.byTooltip('New note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Freehand thought');
      await tester.enterText(find.byKey(const Key('note-content-field')), 'Independent of the reading position');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.notes.single.bookId, book.id);
      expect(store.notes.single.content, 'Independent of the reading position');
      expect(store.notes.single.location, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('invalid requested location does not fall back to the resume position', (tester) async {
    final store = DataStore()
      ..loadData(
        books: [buildTestBook(id: 'epub-book', fileFormat: BookFormat.epub)],
      );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: ReaderPage(bookId: 'epub-book', location: '[]'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This saved location could not be opened.'), findsOneWidget);
    expect(find.byType(PapyrusReader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host theme changes keep the same open document and avoid rereading media', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesProvider(await SharedPreferences.getInstance());

    final dataStore = DataStore()
      ..loadData(
        books: [buildTestBook(id: 'epub-book', fileFormat: BookFormat.epub)],
      );

    final gate = Completer<void>();
    final cache = _ReaderMediaCache(gate: gate);
    addTearDown(dataStore.dispose);
    late StateSetter updateTheme;
    var dark = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: dataStore),
          ChangeNotifierProvider.value(value: preferences),
          Provider<MediaCacheService>.value(value: cache),
          Provider<BookImportService>(create: (_) => BookImportService()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _ReaderAuth()),
        ],
        child: StatefulBuilder(
          builder: (context, setState) {
            updateTheme = setState;

            return MaterialApp(
              theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
              home: const ReaderPage(bookId: 'epub-book'),
            );
          },
        ),
      ),
    );

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final loaderCenter = tester.getCenter(find.byType(CircularProgressIndicator));
    expect(loaderCenter, const Offset(400, 300));
    gate.complete();

    for (var frame = 0; frame < 8 && find.byType(PapyrusReader).evaluate().isEmpty; frame++) {
      await tester.pump();
    }

    expect(cache.loads, 1, reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' / '));
    expect(find.byType(PapyrusReader), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(tester.getCenter(find.byType(CircularProgressIndicator)), loaderCenter);
    final before = tester.widget<PapyrusReader>(find.byType(PapyrusReader)).document;
    updateTheme(() => dark = true);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<PapyrusReader>(find.byType(PapyrusReader)).document, same(before));
    expect(cache.loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('profile switch during media loading ends the spinner without opening the old book', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesProvider(await SharedPreferences.getInstance());
    final book = buildTestBook(id: 'shared-id', fileFormat: BookFormat.epub);
    final originalProfile = _ReaderBookRepository();
    final dataStore = DataStore(bookRepository: originalProfile)..loadData(books: [book]);
    final gate = Completer<void>();
    final cache = _ReaderMediaCache(gate: gate);
    addTearDown(dataStore.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: dataStore),
          ChangeNotifierProvider.value(value: preferences),
          Provider<MediaCacheService>.value(value: cache),
          Provider<BookImportService>(create: (_) => BookImportService()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _ReaderAuth()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ReaderPage(bookId: 'shared-id')),
                ),
                child: const Text('Open book'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(cache.loads, 1);
    originalProfile.isCurrent = false;
    dataStore.loadData(books: [book.copyWith(title: 'Other profile book')]);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(PapyrusReader), findsNothing);
    expect(find.text('Your library changed. Reopen this book from the library.'), findsOneWidget);
    expect(dataStore.getBook(book.id)!.title, 'Other profile book');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open book'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains when a book format is not supported', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesProvider(await SharedPreferences.getInstance());

    final dataStore = DataStore()
      ..loadData(
        books: [buildTestBook(id: 'mobi-book', fileFormat: BookFormat.mobi)],
      );

    addTearDown(dataStore.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: dataStore),
          ChangeNotifierProvider.value(value: preferences),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'mobi-book')),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('This book format is not supported yet.'), findsOneWidget);
  });
}

class _ReaderMediaCache extends MediaCacheService {
  _ReaderMediaCache({this.gate});

  final Completer<void>? gate;
  int loads = 0;

  @override
  Future<Uint8List> ensureBookFileCached(
    Book book, {
    required LocalBookFileReader readLocalBookFile,
    required LocalBookFileWriter writeLocalBookFile,
    required MediaDownloader downloadMedia,
  }) async {
    loads++;
    await gate?.future;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _ReaderAuth extends ChangeNotifier implements AuthProvider {
  @override
  Future<Uint8List> downloadMedia(String assetId) async => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReaderBookRepository extends InMemoryBookRepository implements EditableBookRepository {
  @override
  bool isCurrent = true;

  @override
  Future<void> update(Book book, {required Book previous}) => upsert(book);
}
