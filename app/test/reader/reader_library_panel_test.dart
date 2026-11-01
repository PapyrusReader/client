import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/reader/reader_library.dart';
import 'package:papyrus/reader/reader_bookmark_button.dart';
import 'package:papyrus/reader/reader_library_panel.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

import '../helpers/test_helpers.dart';

class _Entities<T> implements EntityRepository<T> {
  _Entities(this.id);
  final String Function(T) id;
  final values = <String, T>{};
  bool fail = false;
  Completer<void>? pending;

  @override
  Future<T?> getById(String id) async => values[id];
  @override
  Future<void> delete(String id) async {
    await pending?.future;
    if (fail) throw StateError('Storage unavailable');
    values.remove(id);
  }

  @override
  Future<void> upsert(T value, {T? previous}) async {
    await pending?.future;
    if (fail) throw StateError('Storage unavailable');
    values[id(value)] = value;
  }
}

class _Repository extends Fake implements EditableBookRepository, LibraryRepository {
  _Repository({this.snapshot = const LibrarySnapshot()});

  final LibrarySnapshot snapshot;

  @override
  bool isCurrent = true;
  @override
  EditableBookRepository get scopedBooks => this;
  @override
  final _Entities<Bookmark> bookmarks = _Entities<Bookmark>((value) => value.id);
  @override
  final _Entities<Annotation> annotations = _Entities<Annotation>((value) => value.id);
  @override
  final _Entities<Note> notes = _Entities<Note>((value) => value.id);
  @override
  Stream<LibrarySnapshot> watchLibrary() => Stream.value(snapshot);
}

void main() {
  final locator = EpubReaderLocator(spineIndex: 2, textOffset: 120, localProgression: .2, totalProgression: .4);
  final selection = ReaderSelection(
    text: 'A remembered passage',
    start: locator,
    end: EpubReaderLocator(spineIndex: 2, textOffset: 140, localProgression: .3, totalProgression: .4),
  );

  final snapshot = ReaderReadySnapshot(
    document: ReaderDocument(id: 'book', format: ReaderFormat.epub, loadBytes: () async => Uint8List(0)),
    preferences: const ReaderPreferences(),
    capabilities: const ReaderCapabilities(),
    locator: locator,
    toc: [ReaderTocEntry(title: 'Third chapter', locator: locator)],
  );

  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark), ('eink', AppTheme.eink)]) {
    testWidgets('contents and settings share header geometry in $name theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = DataStore(bookRepository: _Repository());
      addTearDown(store.dispose);
      final library = ReaderLibrary(store: store, bookId: 'book');

      final controller = ReaderController(
        registry: ReaderEngineRegistry([
          ReaderEngineRegistration(
            formats: const {ReaderFormat.pdf},
            factory: () => PdfReaderEngine(facadeFactory: (_) async => _PanelPdfFacade()),
          ),
        ]),
      );

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: PapyrusReader(
            document: ReaderDocument(id: 'book', format: ReaderFormat.pdf, loadBytes: () async => Uint8List(0)),
            controller: controller,
            theme: ReaderThemeData.fromTheme(theme).copyWith(sidePanelWidth: 420),
            builders: ReaderUiBuilders(
              tableOfContents: (_, panel) => ReaderLibraryPanel(panel: panel, library: library),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('reader-content'))));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      final settingsTitle = find.text('Reading settings');
      final titleStyle = tester.widget<Text>(settingsTitle).style;
      final titlePosition = tester.getTopLeft(settingsTitle);
      final closeBounds = tester.getRect(find.byTooltip('Close panel'));

      Finder headerBorder(Finder title) => find
          .ancestor(
            of: title,
            matching: find.byWidgetPredicate((widget) {
              if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
                return false;
              }

              final border = (widget.decoration as BoxDecoration).border;
              return border is Border && border.bottom.style == BorderStyle.solid;
            }),
          )
          .first;

      final headerBounds = tester.getRect(headerBorder(settingsTitle));
      final headerDecoration = tester.widget<DecoratedBox>(headerBorder(settingsTitle)).decoration;
      await tester.tap(find.byTooltip('Close panel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Table of contents'));
      await tester.pumpAndSettle();
      final contentsTitle = find.text('Contents');
      expect(tester.widget<Text>(contentsTitle).style, titleStyle);
      expect(tester.getTopLeft(contentsTitle), titlePosition);
      expect(tester.getRect(find.byTooltip('Close panel')), closeBounds);
      expect(tester.getRect(headerBorder(contentsTitle)), headerBounds);
      expect(tester.widget<DecoratedBox>(headerBorder(contentsTitle)).decoration, headerDecoration);
      expect(find.text('Bookmarks'), findsOneWidget);
      await tester.tap(find.byTooltip('Close panel'));
      await tester.pumpAndSettle();
      expect(find.text('Contents'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('saved EPUB titles follow the nearest preceding section, including selection starts', () {
    final store = DataStore(bookRepository: _Repository());
    addTearDown(store.dispose);
    final library = ReaderLibrary(store: store, bookId: 'book');

    EpubReaderLocator at(int offset) => EpubReaderLocator(
      spineIndex: 2,
      textOffset: offset,
      localProgression: offset / 1000,
      totalProgression: .4,
    );

    final toc = [
      ReaderTocEntry(title: 'Later section', locator: at(500)),
      ReaderTocEntry(
        title: 'Chapter start',
        locator: at(0),
        children: [ReaderTocEntry(title: 'Early section', locator: at(100))],
      ),
      ReaderTocEntry(
        title: 'Unresolved section',
        locator: EpubReaderLocator(spineIndex: 2, anchor: 'missing', localProgression: 0, totalProgression: .4),
      ),
    ];

    final current = ReaderReadySnapshot(
      document: snapshot.document,
      preferences: snapshot.preferences,
      capabilities: snapshot.capabilities,
      locator: at(600),
      toc: toc,
    );

    expect(library.location(current).chapterTitle, 'Later section');

    for (final (offset, title) in [(50, 'Chapter start'), (100, 'Early section'), (120, 'Early section')]) {
      final selected = ReaderSelection(text: 'Text', start: at(offset), end: at(offset + 10));
      final saved = library.location(current, selection: selected);
      expect(saved.chapterTitle, title);
      expect(saved.readerLocator, selected.start.toJson());
    }
  });

  test('saved EPUB titles compare progression when offsets are unavailable', () {
    final store = DataStore(bookRepository: _Repository());
    addTearDown(store.dispose);
    final library = ReaderLibrary(store: store, bookId: 'book');

    EpubReaderLocator at(double progress) => EpubReaderLocator(
      spineIndex: 2,
      localProgression: progress,
      totalProgression: .4,
    );

    final current = ReaderReadySnapshot(
      document: snapshot.document,
      preferences: snapshot.preferences,
      capabilities: snapshot.capabilities,
      locator: at(.3),
      toc: [
        ReaderTocEntry(title: 'Start', locator: at(0)),
        ReaderTocEntry(title: 'Early section', locator: at(.2)),
        ReaderTocEntry(title: 'Later section', locator: at(.5)),
      ],
    );

    expect(library.location(current).chapterTitle, 'Early section');
  });

  for (final (width, eink) in [(390.0, false), (1000.0, false), (390.0, true)]) {
    testWidgets('create, view and navigate saved reader items at width $width, eink $eink', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      final repository = _Repository();
      final store = DataStore(bookRepository: repository);
      final library = ReaderLibrary(store: store, bookId: 'book');
      final controller = ReaderController(registry: ReaderEngineRegistry.defaults());
      addTearDown(controller.dispose);
      addTearDown(store.dispose);
      ReaderLocator? navigated;
      late BuildContext hostContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: eink ? AppTheme.eink : AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: width < 720 ? width : 420,
                    child: ReaderLibraryPanel(
                      library: library,
                      panel: ReaderPanelContext(
                        snapshot: snapshot,
                        controller: controller,
                        close: () {},
                        showHeader: width >= 720,
                        buildHeader: (_, title) => Text(title),
                        navigate: (locator) => navigated = locator,
                        buildContents: (_) => const Center(child: Text('Third chapter')),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      final bookmarkFab = find.byTooltip('Bookmark this location');
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final panelBounds = tester.getRect(find.byType(ReaderLibraryPanel));
      final bookmarkBounds = tester.getRect(bookmarkFab);
      expect(bookmarkBounds.right, panelBounds.right - 16);
      expect(bookmarkBounds.bottom, panelBounds.bottom - 16);
      await tester.tap(bookmarkFab);
      await tester.pumpAndSettle();
      expect(repository.bookmarks.values.values.single.readerLocator, locator.toJson());
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsWidgets);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNotNull);
      await library.addBookmark(hostContext, snapshot);
      expect(repository.bookmarks.values, hasLength(1));
      await tester.tap(find.text('Third chapter'));
      expect(navigated, locator);
      final bookmark = repository.bookmarks.values.values.single;
      library.editBookmark(hostContext, bookmark);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Note (optional)'), 'Return here');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.bookmarks.values.values.single.readerLocator, locator.toJson());
      expect(repository.bookmarks.values.values.single.position, bookmark.position);
      expect(repository.bookmarks.values.values.single.note, 'Return here');

      library.annotate(hostContext, snapshot, selection);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.annotations.values.values.single.selectedText, selection.text);
      expect(library.highlights.single.selection.start, locator);
      await tester.ensureVisible(find.text('Annotations'));
      await tester.tap(find.text('Annotations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(selection.text));
      await tester.pumpAndSettle();
      expect(find.text('Go to passage'), findsOneWidget);
      await tester.tap(find.text('Go to passage'));
      await tester.pumpAndSettle();
      expect(navigated, locator);

      final highlight = library.highlights.single;
      library.editHighlight(hostContext, highlight);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Note (optional)'), 'Edited from the passage');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.annotations.values.values.single.note, 'Edited from the passage');
      expect(repository.annotations.values.values.single.location.selection, selection.toJson());
      library.removeHighlight(hostContext, highlight);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.highlights, hasLength(1));
      repository.annotations.fail = true;
      library.removeHighlight(hostContext, highlight);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(repository.annotations.values, hasLength(1));
      expect(library.highlights, hasLength(1));
      expect(find.text('Could not delete item. Try again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      repository.annotations.fail = false;
      library.removeHighlight(hostContext, highlight);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(repository.annotations.values, isEmpty);
      expect(library.highlights, isEmpty);

      await tester.ensureVisible(find.text('Notes'));
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      final noteFab = find.byTooltip('Add note');
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final noteBounds = tester.getRect(noteFab);
      expect(noteBounds.right, panelBounds.right - 16);
      expect(noteBounds.bottom, panelBounds.bottom - 16);
      await tester.tap(noteFab);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'My thought');
      await tester.enterText(find.byKey(const Key('note-content-field')), 'The full note content');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.notes.values.values.single.location, isNull);
      await tester.tap(find.text('My thought'));
      await tester.pumpAndSettle();
      expect(find.text('The full note content'), findsWidgets);
      expect(find.text('Go to passage'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (format, pageNumber, canNavigate) in [
    (BookFormat.pdf, 20, true),
    (BookFormat.pdf, 0, false),
    (BookFormat.epub, 20, false),
  ]) {
    testWidgets('page-only saved items in $format at page $pageNumber', (tester) async {
      final book = buildTestBook(id: 'book', fileFormat: format, pageCount: 100);
      final repository = _Repository(
        snapshot: LibrarySnapshot(
          books: [book],
          bookmarks: [
            Bookmark(
              id: 'bookmark',
              bookId: book.id,
              position: .2,
              pageNumber: pageNumber,
              note: 'Page bookmark',
              createdAt: DateTime.utc(2026),
            ),
          ],
          annotations: [
            Annotation(
              id: 'annotation',
              bookId: book.id,
              selectedText: 'Page annotation',
              location: BookLocation(pageNumber: pageNumber),
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      final store = DataStore(bookRepository: repository);
      final library = ReaderLibrary(store: store, bookId: book.id);
      final controller = ReaderController(registry: ReaderEngineRegistry.defaults());
      addTearDown(controller.dispose);
      addTearDown(store.dispose);
      ReaderLocator? navigated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderLibraryPanel(
              library: library,
              panel: ReaderPanelContext(
                snapshot: snapshot,
                controller: controller,
                close: () {},
                buildHeader: (_, title) => Text(title),
                navigate: (locator) => navigated = locator,
                buildContents: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page bookmark'));
      await tester.pumpAndSettle();

      if (canNavigate) {
        expect((navigated as PdfReaderLocator).pageIndex, 19);
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(navigated, isNull);
        expect(find.text('Go to passage'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }

      navigated = null;
      await tester.tap(find.text('Annotations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page annotation'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      if (canNavigate) {
        await tester.tap(find.text('Go to passage'));
        await tester.pumpAndSettle();
        expect((navigated as PdfReaderLocator).pageIndex, 19);
      } else {
        expect(find.text('Go to passage'), findsNothing);
        expect(navigated, isNull);
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('bookmark feedback tracks pending, failed, saved and deleted states', (tester) async {
    final repository = _Repository();
    final store = DataStore(bookRepository: repository);
    final library = ReaderLibrary(store: store, bookId: 'book');
    addTearDown(store.dispose);
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return ReaderBookmarkButton(library: library, snapshot: snapshot);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.bookmarks.fail = true;
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pumpAndSettle();
    expect(repository.bookmarks.values, isEmpty);
    expect(find.byTooltip('Add bookmark'), findsOneWidget);
    expect(find.text('Could not save bookmark. Try again.'), findsOneWidget);
    repository.bookmarks.fail = false;
    repository.bookmarks.pending = Completer<void>();
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pump();
    expect(find.byTooltip('Saving bookmark…'), findsOneWidget);
    await library.addBookmark(hostContext, snapshot);
    repository.bookmarks.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(repository.bookmarks.values, hasLength(1));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final bookmark = repository.bookmarks.values.values.single;
    final reflowed = ReaderReadySnapshot(
      document: snapshot.document,
      preferences: snapshot.preferences,
      capabilities: snapshot.capabilities,
      locator: EpubReaderLocator(spineIndex: 2, textOffset: 100, localProgression: .1, totalProgression: .3),
      coverage: const [ReaderContentCoverage(key: 'epub:2:1000', start: .1, end: .2)],
    );
    expect(library.bookmarkAt(reflowed)?.id, bookmark.id);
    await library.addBookmark(hostContext, reflowed);
    expect(repository.bookmarks.values, hasLength(1));
    repository.bookmarks.fail = true;
    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pumpAndSettle();
    expect(repository.bookmarks.values, hasLength(1));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.text('Could not remove bookmark. Try again.'), findsOneWidget);
    repository.bookmarks.fail = false;
    repository.bookmarks.pending = Completer<void>();
    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pump();
    expect(find.byTooltip('Removing bookmark…'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    await library.toggleBookmark(hostContext, snapshot);
    repository.bookmarks.pending!.complete();
    await tester.pumpAndSettle();
    expect(repository.bookmarks.values, isEmpty);
    expect(find.byTooltip('Add bookmark'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pumpAndSettle();
    expect(repository.bookmarks.values, hasLength(1));
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed and stale annotation editors retain their draft', (tester) async {
    final repository = _Repository();
    final store = DataStore(bookRepository: repository);
    final library = ReaderLibrary(store: store, bookId: 'book');
    addTearDown(store.dispose);
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    library.annotate(hostContext, snapshot, selection);
    await tester.pumpAndSettle();
    repository.annotations.fail = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('New annotation'), findsOneWidget);
    expect(repository.annotations.values, isEmpty);
    repository.annotations.fail = false;
    repository.isCurrent = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('New annotation'), findsOneWidget);
    expect(repository.annotations.values, isEmpty);
    expect(library.highlights, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _PanelPdfFacade implements PdfFacade {
  @override
  int get pageCount => 3;

  @override
  List<PdfFacadeOutlineEntry> get outline => const [];

  @override
  Future<void> showPage(int pageIndex, double pageOffset) async {}

  @override
  Widget buildViewport(PdfViewportConfiguration configuration) => const SizedBox.expand();
}
