import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/collection_grid_size.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_card.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/library/book_grid.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';
import 'package:papyrus/widgets/library/collection_view_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  group('BookGrid ordinary behavior', () {
    testWidgets('grid density follows available content width inside a desktop shell', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 500,
                child: ChangeNotifierProvider(
                  create: (_) => LibraryProvider(),
                  child: BookGrid(
                    books: [_book(id: 'one', title: 'A book')],
                    libraryViewMode: LibraryViewMode.grid,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final grid = tester.widget<GridView>(find.byType(GridView));
      expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders books in a GridView', (tester) async {
      final books = [_book(id: 'book-1', title: 'First Book'), _book(id: 'book-2', title: 'Second Book')];
      await tester.pumpWidget(_buildGrid(books: books));
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(BookCard), findsNWidgets(2));
    });

    testWidgets('renders an empty grid without items', (tester) async {
      await tester.pumpWidget(_buildGrid(books: const []));
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(BookCard), findsNothing);
      expect(find.byType(AcquisitionPlaceholderCard), findsNothing);
    });
  });

  group('BookGrid acquisition reconciliation', () {
    testWidgets('renders a job without a synchronized book once as an orphan', (tester) async {
      final orphan = _job(id: 'orphan-job', bookId: null, title: 'Waiting for Sync');
      await tester.pumpWidget(_buildGrid(books: const [], placeholderJobs: [orphan]));
      expect(find.byType(BookCard), findsNothing);
      expect(find.byType(AcquisitionPlaceholderCard), findsOneWidget);
      expect(find.text('Waiting for Sync'), findsOneWidget);
    });

    testWidgets('attaches a linked job and does not render an orphan', (tester) async {
      final book = _book(id: 'book-1', title: 'Synchronized Book');
      final linked = _job(id: 'linked-job', bookId: book.id, title: book.title);

      await tester.pumpWidget(
        _buildGrid(books: [book], acquisitionJobsByBookId: {book.id: linked}, placeholderJobs: [linked]),
      );

      final card = tester.widget<BookCard>(_bookCard(book.id));
      expect(card.acquisitionJob, same(linked));
      expect(find.byType(BookCard), findsOneWidget);
      expect(find.byType(AcquisitionPlaceholderCard), findsNothing);
    });

    testWidgets('defensively attaches a linked placeholder job by book id', (tester) async {
      final book = _book(id: 'book-1', title: 'Synchronized Book');
      final linked = _job(id: 'linked-job', bookId: book.id, title: book.title);
      await tester.pumpWidget(_buildGrid(books: [book], placeholderJobs: [linked]));
      expect(tester.widget<BookCard>(_bookCard(book.id)).acquisitionJob, same(linked));
      expect(find.byType(AcquisitionPlaceholderCard), findsNothing);
    });

    testWidgets('claims a duplicate linked job id for the first book only', (tester) async {
      final firstBook = _book(id: 'book-1', title: 'First Book');
      final secondBook = _book(id: 'book-2', title: 'Second Book');
      final firstJob = _job(id: 'shared-job', bookId: firstBook.id, title: firstBook.title);
      final secondJob = _job(id: 'shared-job', bookId: secondBook.id, title: secondBook.title);
      final acquisitionSelections = <String>[];
      final ordinaryTaps = <String>[];

      await tester.pumpWidget(
        _buildGrid(
          books: [firstBook, secondBook],
          acquisitionJobsByBookId: {secondBook.id: secondJob, firstBook.id: firstJob},
          selectedAcquisitionJobIds: const {'shared-job'},
          onAcquisitionSelectionToggle: (job) => acquisitionSelections.add(job.id),
          onBookTap: (book) => ordinaryTaps.add(book.id),
        ),
      );

      final firstCard = tester.widget<BookCard>(_bookCard(firstBook.id));
      final secondCard = tester.widget<BookCard>(_bookCard(secondBook.id));
      expect(firstCard.acquisitionJob, same(firstJob));
      expect(firstCard.isSelectionMode, isTrue);
      expect(firstCard.isSelected, isTrue);
      expect(secondCard.acquisitionJob, isNull);
      expect(secondCard.isSelectionMode, isFalse);
      expect(secondCard.isSelected, isFalse);
      await tester.tap(_bookCard(firstBook.id));
      await tester.tap(_bookCard(secondBook.id));
      expect(acquisitionSelections, ['shared-job']);
      expect(ordinaryTaps, [secondBook.id]);
    });

    testWidgets('claims a map and placeholder duplicate id in books order', (tester) async {
      final placeholderBook = _book(id: 'book-placeholder', title: 'Placeholder Winner');
      final mappedBook = _book(id: 'book-mapped', title: 'Mapped Loser');
      final placeholderJob = _job(id: 'shared-job', bookId: placeholderBook.id, title: placeholderBook.title);
      final mappedJob = _job(id: 'shared-job', bookId: mappedBook.id, title: mappedBook.title);

      await tester.pumpWidget(
        _buildGrid(
          books: [placeholderBook, mappedBook],
          acquisitionJobsByBookId: {mappedBook.id: mappedJob},
          placeholderJobs: [placeholderJob],
        ),
      );

      expect(tester.widget<BookCard>(_bookCard(placeholderBook.id)).acquisitionJob, same(placeholderJob));
      expect(tester.widget<BookCard>(_bookCard(mappedBook.id)).acquisitionJob, isNull);
      expect(find.byType(AcquisitionPlaceholderCard), findsNothing);
    });

    testWidgets('deduplicates repeated orphan ids and book ids', (tester) async {
      final first = _job(id: 'job-1', bookId: 'pending-book', title: 'First');
      final duplicateId = _job(id: 'job-1', bookId: null, title: 'Duplicate ID');
      final duplicateBook = _job(id: 'job-2', bookId: 'pending-book', title: 'Duplicate Book');
      await tester.pumpWidget(_buildGrid(books: const [], placeholderJobs: [first, duplicateId, duplicateBook]));
      expect(find.byType(AcquisitionPlaceholderCard), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Duplicate ID'), findsNothing);
      expect(find.text('Duplicate Book'), findsNothing);
    });

    testWidgets('orders synchronized books before orphan placeholders', (tester) async {
      final first = _book(id: 'book-1', title: 'First Book');
      final second = _book(id: 'book-2', title: 'Second Book');
      final orphan = _job(id: 'orphan-job', bookId: null, title: 'Orphan Job');
      await tester.pumpWidget(_buildGrid(books: [first, second], placeholderJobs: [orphan]));
      final firstPosition = tester.getTopLeft(_bookCard(first.id));
      final secondPosition = tester.getTopLeft(_bookCard(second.id));
      final orphanPosition = tester.getTopLeft(find.byType(AcquisitionPlaceholderCard));
      expect(firstPosition.dy, secondPosition.dy);
      expect(orphanPosition.dy, greaterThan(firstPosition.dy));
    });

    testWidgets('routes linked and orphan interactions to acquisition callbacks', (tester) async {
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);
      final orphanJob = _job(id: 'job-orphan', bookId: null, title: 'Orphan Book');
      final acquisitionTaps = <String>[];
      final acquisitionToggles = <String>[];
      final bookTaps = <String>[];

      await tester.pumpWidget(
        _buildGrid(
          books: [linkedBook],
          onBookTap: (book) => bookTaps.add(book.id),
          acquisitionJobsByBookId: {linkedBook.id: linkedJob},
          placeholderJobs: [orphanJob],
          onAcquisitionTap: (job) => acquisitionTaps.add(job.id),
          onAcquisitionSelectionToggle: (job) => acquisitionToggles.add(job.id),
        ),
      );

      await tester.tap(_bookCard(linkedBook.id));
      await tester.tap(find.byType(AcquisitionPlaceholderCard));
      await tester.longPress(_bookCard(linkedBook.id));
      await tester.longPress(find.byType(AcquisitionPlaceholderCard));
      expect(acquisitionTaps, ['job-linked', 'job-orphan']);
      expect(acquisitionToggles, ['job-linked', 'job-orphan']);
      expect(bookTaps, isEmpty);
    });

    testWidgets('routes linked and orphan selection-mode taps to acquisition toggles', (tester) async {
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);
      final orphanJob = _job(id: 'job-orphan', bookId: null, title: 'Orphan Book');
      final acquisitionTaps = <String>[];
      final acquisitionToggles = <String>[];

      await tester.pumpWidget(
        _buildGrid(
          books: [linkedBook],
          acquisitionJobsByBookId: {linkedBook.id: linkedJob},
          placeholderJobs: [orphanJob],
          selectedAcquisitionJobIds: const {'job-linked'},
          onAcquisitionTap: (job) => acquisitionTaps.add(job.id),
          onAcquisitionSelectionToggle: (job) => acquisitionToggles.add(job.id),
        ),
      );

      final linkedCard = tester.widget<BookCard>(_bookCard(linkedBook.id));
      final orphanCard = tester.widget<AcquisitionPlaceholderCard>(find.byType(AcquisitionPlaceholderCard));
      expect(linkedCard.isSelected, isTrue);
      expect(orphanCard.isSelected, isFalse);
      await tester.tap(_bookCard(linkedBook.id));
      await tester.tap(find.byType(AcquisitionPlaceholderCard));
      expect(acquisitionToggles, ['job-linked', 'job-orphan']);
      expect(acquisitionTaps, isEmpty);
    });

    testWidgets('does not open ordinary book actions for a linked job without callbacks', (tester) async {
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);
      await tester.pumpWidget(_buildGrid(books: [linkedBook], acquisitionJobsByBookId: {linkedBook.id: linkedJob}));
      await tester.longPress(_bookCard(linkedBook.id));
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not use the ordinary tap callback for a linked job without an acquisition callback', (
      tester,
    ) async {
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);
      final ordinaryTaps = <String>[];

      await tester.pumpWidget(
        _buildGrid(
          books: [linkedBook],
          acquisitionJobsByBookId: {linkedBook.id: linkedJob},
          onBookTap: (book) => ordinaryTaps.add(book.id),
        ),
      );

      await tester.tap(_bookCard(linkedBook.id));
      expect(ordinaryTaps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not expose provider favorite mutation for linked jobs', (tester) async {
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final ordinaryBook = _book(id: 'book-ordinary', title: 'Ordinary Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);

      await tester.pumpWidget(
        _buildGrid(books: [linkedBook, ordinaryBook], acquisitionJobsByBookId: {linkedBook.id: linkedJob}),
      );

      final linkedCard = tester.widget<BookCard>(_bookCard(linkedBook.id));
      final ordinaryCard = tester.widget<BookCard>(_bookCard(ordinaryBook.id));
      expect(linkedCard.onToggleFavorite, isNull);
      expect(ordinaryCard.onToggleFavorite, isNotNull);
    });

    testWidgets('ordinary books keep ordinary taps and provider selection', (tester) async {
      final provider = LibraryProvider();
      final ordinary = _book(id: 'book-ordinary', title: 'Ordinary Book');
      final tappedBooks = <String>[];

      await tester.pumpWidget(
        _buildGrid(
          books: [ordinary],
          libraryProvider: provider,
          onBookTap: (book) => tappedBooks.add(book.id),
          onAcquisitionTap: (_) => fail('ordinary book used acquisition tap'),
          onAcquisitionSelectionToggle: (_) => fail('ordinary book used acquisition selection'),
        ),
      );

      await tester.tap(_bookCard(ordinary.id));
      expect(tappedBooks, [ordinary.id]);
      tester.widget<BookCard>(_bookCard(ordinary.id)).onEnterSelectionMode!.call();
      await tester.pump();
      expect(provider.isBookSelected(ordinary.id), isTrue);
    });

    testWidgets('keeps ordinary and acquisition selection state independent', (tester) async {
      final provider = LibraryProvider()..enterSelectionMode('book-ordinary');
      final ordinary = _book(id: 'book-ordinary', title: 'Ordinary Book');
      final linkedBook = _book(id: 'book-linked', title: 'Linked Book');
      final linkedJob = _job(id: 'job-linked', bookId: linkedBook.id, title: linkedBook.title);

      await tester.pumpWidget(
        _buildGrid(
          books: [ordinary, linkedBook],
          libraryProvider: provider,
          acquisitionJobsByBookId: {linkedBook.id: linkedJob},
        ),
      );

      final ordinaryCard = tester.widget<BookCard>(_bookCard(ordinary.id));
      final unselectedLinkedCard = tester.widget<BookCard>(_bookCard(linkedBook.id));
      expect(ordinaryCard.isSelectionMode, isTrue);
      expect(ordinaryCard.isSelected, isTrue);
      expect(unselectedLinkedCard.isSelectionMode, isFalse);
      expect(unselectedLinkedCard.isSelected, isFalse);

      await tester.pumpWidget(
        _buildGrid(
          books: [ordinary, linkedBook],
          libraryProvider: provider,
          acquisitionJobsByBookId: {linkedBook.id: linkedJob},
          selectedAcquisitionJobIds: const {'job-linked'},
        ),
      );

      final selectedLinkedCard = tester.widget<BookCard>(_bookCard(linkedBook.id));
      expect(selectedLinkedCard.isSelectionMode, isTrue);
      expect(selectedLinkedCard.isSelected, isTrue);
      expect(provider.isBookSelected(linkedBook.id), isFalse);
    });
  });

  group('BookGrid responsiveness', () {
    testWidgets('the e-ink column slider retains a drag and keyboard steps with its animation muted', (tester) async {
      const screen = Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.reset);
      final provider = LibraryProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        _buildGrid(
          books: [_book(id: 'book', title: 'A book')],
          libraryProvider: provider,
          screenSize: screen,
          showViewControls: true,
          theme: AppTheme.eink,
        ),
      );

      await tester.tap(find.text('View mode'));
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      final element = tester.element(slider);
      expect(TickerMode.valuesOf(element).enabled, isFalse);
      final bounds = tester.getRect(slider).deflate(12);
      final gesture = await tester.startGesture(bounds.centerLeft);
      await gesture.moveTo(bounds.center);
      await tester.pump();
      await gesture.moveTo(bounds.centerRight);
      await tester.pump();
      await gesture.up();
      expect(tester.element(slider), same(element));
      expect(tester.widget<Slider>(slider).value, 3);
      expect(tester.getSemantics(slider).getSemanticsData().value, '4 columns');

      final semantics = tester.getSemantics(slider);
      semantics.owner!.performAction(semantics.id, SemanticsAction.focus);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, 2);
      expect(tester.getSemantics(slider).getSemanticsData().value, '3 columns');
    });

    testWidgets('aligns covers and metadata for short, long, and downloading titles', (tester) async {
      const screenSize = Size(560, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screenSize;
      addTearDown(tester.view.reset);
      final short = _book(id: 'short', title: 'Short').copyWith(author: 'First');
      final long = _book(id: 'long', title: 'A book with a much longer title that will wrap').copyWith(
        author: 'Second',
        currentPosition: 0.5,
      );

      await tester.pumpWidget(
        _buildGrid(
          books: [short, long],
          placeholderJobs: [_job(id: 'transfer', bookId: null, title: 'A pending book', transferSpeed: 1024)],
          screenSize: screenSize,
        ),
      );

      final covers = find.byType(CoverImage);
      expect(tester.getBottomLeft(covers.first).dy, tester.getBottomLeft(covers.last).dy);
      final bylineOffset = tester.getTopLeft(find.text('First')).dy;
      expect(tester.getTopLeft(find.text('Second')).dy, bylineOffset);
      expect(tester.getTopLeft(find.text('Downloading 42%')).dy, bylineOffset);
    });

    testWidgets('tighter column gaps widen book cards at the same row height', (tester) async {
      const screenSize = Size(384, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screenSize;
      addTearDown(tester.view.reset);
      final provider = LibraryProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        _buildGrid(
          books: [_book(id: 'book-1', title: 'A book with a two-line title')],
          libraryProvider: provider,
          screenSize: screenSize,
        ),
      );

      final contentWidth = screenSize.width - 32;

      for (final option in collectionGridSizeOptions(contentWidth)) {
        provider.gridDensity.width = option.preferredWidth;
        await tester.pumpAndSettle();
        final layout = collectionGridLayout(contentWidth, itemWidth: option.preferredWidth);
        final size = tester.getSize(_bookCard('book-1'));
        expect(size.height, closeTo(layout.itemWidth / layout.childAspectRatio, .001));
        expect(
          size.width * option.columns + 6 * (option.columns - 1),
          closeTo(contentWidth, .001),
          reason: '${option.columns} columns',
        );
      }
    });

    for (final width in [320.0, 400.0, 1280.0, 1850.0]) {
      testWidgets('each slider step selects its column count with the keyboard at width $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.reset);
        final provider = LibraryProvider()..gridDensity.width = CollectionGridSize.minimum;
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          _buildGrid(
            books: [_book(id: 'book-1', title: 'A book')],
            libraryProvider: provider,
            screenSize: Size(width, 1000),
            showViewControls: true,
          ),
        );

        await tester.tap(find.text('View mode'));
        await tester.pumpAndSettle();
        final slider = find.byType(Slider);
        final options = collectionGridSizeOptions(width - 32);

        if (width < 600) {
          expect(options.map((option) => option.columns), [1, 2, 3, 4]);
        }

        expect(tester.widget<Slider>(slider).divisions, options.length - 1);
        final sliderSemantics = tester.getSemantics(slider);
        sliderSemantics.owner!.performAction(sliderSemantics.id, SemanticsAction.focus);
        await tester.pumpAndSettle();

        for (final (index, option) in options.reversed.indexed) {
          final label = '${option.columns} ${option.columns == 1 ? 'column' : 'columns'}';

          if (index > 0) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            await tester.pumpAndSettle();
          }

          final delegate =
              tester.widget<GridView>(find.byType(GridView)).gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

          expect(delegate.crossAxisCount, option.columns);
          final sliderData = tester.getSemantics(slider).getSemanticsData();
          expect(sliderData.label, 'Columns');
          expect(sliderData.value, label);
          expect(find.text('${option.columns}'), findsOneWidget);
          expect(delegate.crossAxisSpacing, width - 32 >= Breakpoints.tablet ? 12 : 6);

          expect(
            tester.getSize(_bookCard('book-1')).width * option.columns +
                delegate.crossAxisSpacing * (option.columns - 1),
            closeTo(width - 32, .001),
          );
        }

        expect(tester.takeException(), isNull);
      });
    }

    for (final (width, scale) in [
      (320.0, 1.0),
      (320.0, 2.0),
      (400.0, 1.0),
      (400.0, 2.0),
      (500.0, 1.0),
      (1280.0, 1.0),
    ]) {
      testWidgets('every density choice fills the row at width $width and text scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.reset);
        final provider = LibraryProvider()..gridDensity.width = CollectionGridSize.minimum;
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          _buildGrid(
            books: [_book(id: 'book-1', title: 'A long book title that uses two lines')],
            placeholderJobs: [_job(id: 'job-1', bookId: null, title: 'A pending book')],
            libraryProvider: provider,
            screenSize: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
          ),
        );

        Size? previous;
        Size? previousCover;

        for (final option in collectionGridSizeOptions(width - 32).reversed) {
          provider.gridDensity.width = option.preferredWidth;
          await tester.pumpAndSettle();
          final actual = tester.getSize(_bookCard('book-1'));
          expect(
            tester.widget<BookCard>(_bookCard('book-1')).compact,
            actual.width < CollectionGridSize.regularMinimum,
          );

          expect(
            tester.widget<AcquisitionPlaceholderCard>(find.byType(AcquisitionPlaceholderCard)).compact,
            actual.width < CollectionGridSize.regularMinimum,
          );

          final cover = tester.getSize(find.descendant(of: _bookCard('book-1'), matching: find.byType(CoverImage)));

          if (previous != null) {
            expect(actual.width, greaterThan(previous.width), reason: '${option.columns} columns');
            expect(actual.height, greaterThanOrEqualTo(previous.height), reason: '${option.columns} columns');
          }

          if (previousCover != null) {
            expect(cover.width, greaterThan(previousCover.width), reason: '${option.columns} columns');

            expect(
              cover.width * cover.height,
              greaterThan(previousCover.width * previousCover.height),
              reason: '${option.columns} columns',
            );
          }

          expect(actual.width, lessThanOrEqualTo(width - 32));
          final grid = tester.widget<GridView>(find.byType(GridView));
          final spacing = (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisSpacing;
          expect(actual.width * option.columns + spacing * (option.columns - 1), closeTo(width - 32, .001));
          expect(tester.getTopLeft(_bookCard('book-1')).dx, 16);

          if (option.columns > 1) {
            expect(
              tester.getTopLeft(find.byType(AcquisitionPlaceholderCard)).dx -
                  tester.getBottomRight(_bookCard('book-1')).dx,
              closeTo(spacing, .001),
            );
          }

          expect(tester.getSize(find.byType(AcquisitionPlaceholderCard)), actual);
          expect(tester.takeException(), isNull);
          previous = actual;
          previousCover = cover;
        }
      });
    }

    testWidgets('resizing covers changes density without dropping books or overflowing a narrow grid', (tester) async {
      final provider = LibraryProvider();
      addTearDown(provider.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1800, 1000);
      addTearDown(tester.view.reset);
      final books = List.generate(8, (index) => _book(id: 'book-$index', title: 'A book with a long title $index'));
      await tester.pumpWidget(_buildGrid(books: books, libraryProvider: provider, screenSize: const Size(1800, 1000)));
      final initialWidth = tester.getSize(_bookCard('book-0')).width;
      provider.gridDensity.width = 240;
      await tester.pumpAndSettle();
      expect(tester.getSize(_bookCard('book-0')).width, greaterThan(initialWidth));
      expect(find.byType(BookCard), findsNWidgets(8));

      for (final width in [120.0, 320.0]) {
        provider.gridDensity.width = width;
        await tester.pumpWidget(_buildGrid(books: books, libraryProvider: provider, screenSize: const Size(280, 800)));
        await tester.pumpAndSettle();
        expect(tester.getSize(_bookCard('book-0')).width, lessThanOrEqualTo(280));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('preserves responsive columns and matching item widths', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final book = _book(id: 'book-1', title: 'Book');
      final orphan = _job(id: 'job-1', bookId: null, title: 'Orphan');

      for (final (width, columns) in const [(400.0, 2), (700.0, 3), (900.0, 5), (1300.0, 7)]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(_buildGrid(books: [book], placeholderJobs: [orphan], screenSize: Size(width, 800)));
        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, columns);
        expect(tester.getSize(_bookCard(book.id)).width, tester.getSize(find.byType(AcquisitionPlaceholderCard)).width);

        expect(
          tester.getSize(_bookCard(book.id)).height,
          tester.getSize(find.byType(AcquisitionPlaceholderCard)).height,
        );
      }
    });
  });
}

Widget _buildGrid({
  required List<Book> books,
  LibraryProvider? libraryProvider,
  ValueChanged<Book>? onBookTap,
  Map<String, AcquisitionJob> acquisitionJobsByBookId = const {},
  List<AcquisitionJob> placeholderJobs = const [],
  Set<String> selectedAcquisitionJobIds = const {},
  ValueChanged<AcquisitionJob>? onAcquisitionTap,
  ValueChanged<AcquisitionJob>? onAcquisitionSelectionToggle,
  Size screenSize = const Size(400, 800),
  bool showViewControls = false,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ChangeNotifierProvider<LibraryProvider>.value(
    value: libraryProvider ?? LibraryProvider(),
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: screenSize, textScaler: textScaler),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: Scaffold(
              floatingActionButton: showViewControls
                  ? Builder(
                      builder: (context) => FilledButton(
                        onPressed: () {
                          libraryProvider!.gridAvailableWidth.value = screenSize.width - 32;
                          showCollectionViewSheet(context, libraryProvider);
                        },
                        child: const Text('View mode'),
                      ),
                    )
                  : null,
              body: BookGrid(
                books: books,
                libraryViewMode: LibraryViewMode.grid,
                onBookTap: onBookTap,
                acquisitionJobsByBookId: acquisitionJobsByBookId,
                placeholderJobs: placeholderJobs,
                selectedAcquisitionJobIds: selectedAcquisitionJobIds,
                onAcquisitionTap: onAcquisitionTap,
                onAcquisitionSelectionToggle: onAcquisitionSelectionToggle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _bookCard(String bookId) {
  return find.byWidgetPredicate((widget) => widget is BookCard && widget.book.id == bookId);
}

Book _book({required String id, required String title}) {
  return Book(
    id: id,
    title: title,
    author: 'Author',
    readingStatus: LibraryReadingStatus.unread,
    currentPosition: 0,
    isFavorite: false,
    fileFormat: BookFormat.epub,
    addedAt: DateTime(2026),
  );
}

AcquisitionJob _job({required String id, required String? bookId, required String title, int? transferSpeed}) {
  return AcquisitionJob(
    id: id,
    endpointId: 'endpoint-1',
    ruleId: null,
    bookId: bookId,
    title: title,
    status: AcquisitionJobStatus.downloading,
    clientReference: null,
    clientHash: 'hash-$id',
    clientState: 'downloading',
    progressBasisPoints: 4200,
    downloadedBytes: 420,
    totalBytes: 1000,
    downloadSpeedBytesPerSecond: transferSpeed,
    etaSeconds: null,
    selectedFilePath: null,
    retryCount: 0,
    error: null,
    nextPollAt: null,
    createdAt: null,
    updatedAt: null,
    submittedAt: null,
    startedAt: null,
    completedAt: null,
    cancelledAt: null,
  );
}
