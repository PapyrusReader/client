import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/pages/shelves_page.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/shelves_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/library/book_grid.dart';
import 'package:papyrus/widgets/library/collection_filter_row.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';
import 'package:papyrus/widgets/shelves/shelf_card.dart';
import 'package:papyrus/widgets/shelves/shelves_filter_chips.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

void main() {
  testWidgets('the open Shelves view sheet follows the grid across a window resize', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final store = createTestDataStore();
    final library = LibraryProvider();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      library.dispose();
      store.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataStore>.value(value: store),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ],
        child: const MaterialApp(home: ShelvesPage()),
      ),
    );

    await tester.tap(find.byTooltip('Change view mode'));
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    final wideDivisions = tester.widget<Slider>(slider).divisions!;
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).divisions, lessThan(wideDivisions));
    expect(tester.widget<Slider>(slider).divisions, collectionGridSizeOptions(400 - 32).length - 1);

    final grid = tester.widget<GridView>(find.byType(GridView));
    final columns = (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
    expect(tester.getSemantics(slider).getSemanticsData().value, '$columns columns');
  });

  testWidgets('Clear all leads the shelf filters and resets them', (tester) async {
    const screen = Size(390, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);
    final store = createTestDataStore();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });

    await tester.pumpWidget(createTestPage(dataStore: store, screenSize: screen, page: const ShelvesPage()));
    final provider = tester.element(find.byType(ShelvesFilterChips)).read<ShelvesProvider>();
    final clearAll = find.widgetWithText(TextButton, 'Clear all');
    expect(clearAll, findsNothing);
    provider.setContentsFilter(ShelfContentsFilter.empty);
    await tester.pumpAndSettle();
    expect(tester.getRect(clearAll).left, lessThan(tester.getRect(find.text('Grid')).left));
    expect(find.descendant(of: clearAll, matching: find.byIcon(Icons.filter_alt_off_outlined)), findsOneWidget);
    await tester.tap(clearAll);
    await tester.pumpAndSettle();
    expect(provider.contentsFilter, ShelfContentsFilter.all);
    expect(clearAll, findsNothing);
  });

  testWidgets('the same density renders equal card sizes and each collection resizes independently', (tester) async {
    const screen = Size(768, 900);
    const collectionWidth = 384.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);
    final library = LibraryProvider();
    final store = createTestDataStore();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      library.dispose();
      store.dispose();
    });

    await tester.pumpWidget(
      createTestPage(
        dataStore: store,
        libraryProvider: library,
        screenSize: screen,
        page: Row(
          children: [
            SizedBox(
              width: collectionWidth,
              child: BookGrid(books: store.books, libraryViewMode: LibraryViewMode.grid),
            ),
            const SizedBox(width: collectionWidth, child: ShelvesPage()),
          ],
        ),
      ),
    );

    final shelves = tester.element(find.byType(ShelvesFilterChips)).read<ShelvesProvider>();
    final options = collectionGridSizeOptions(collectionWidth - Spacing.md * 2);
    final book = find.byType(BookCard).first;
    final shelf = find.byType(ShelfCard).first;

    for (final option in options) {
      final previousShelfSize = tester.getSize(shelf);
      library.gridDensity.width = option.preferredWidth;
      await tester.pumpAndSettle();
      expect(tester.getSize(shelf), previousShelfSize);
      shelves.gridDensity.width = option.preferredWidth;
      await tester.pumpAndSettle();
      expect(tester.getSize(shelf), tester.getSize(book), reason: '${option.columns} columns');
      expect(tester.widget<ShelfCard>(shelf).compact, tester.widget<BookCard>(book).compact);
    }
  });

  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final layout in [
      (screen: const Size(320, 1100), width: 320.0, scale: 1.0),
      (screen: const Size(400, 1100), width: 400.0, scale: 1.0),
      (screen: const Size(320, 1100), width: 320.0, scale: 2.0),
      (screen: const Size(1200, 1100), width: 560.0, scale: 1.0),
      (screen: const Size(1600, 1100), width: 1200.0, scale: 2.0),
    ]) {
      testWidgets('shelf columns fill and align at ${layout.width}, scale ${layout.scale}, ${theme.brightness}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.screen;
        addTearDown(tester.view.reset);

        final store = createTestDataStore(
          books: [],
          shelves: List.generate(20, (i) => buildTestShelf(id: 'shelf-$i', name: 'Shelf $i with a long title')),
        );

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
        });

        await tester.pumpWidget(
          createTestPage(
            dataStore: store,
            screenSize: layout.screen,
            page: Theme(
              data: theme,
              child: MediaQuery(
                data: MediaQueryData(size: layout.screen, textScaler: TextScaler.linear(layout.scale)),
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(width: layout.width, child: const ShelvesPage()),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final provider = tester.element(find.byType(ShelvesFilterChips)).read<ShelvesProvider>();
        provider.setContentsFilter(ShelfContentsFilter.empty);
        await tester.pumpAndSettle();
        final filterRow = find.byType(CollectionFilterRow);
        expect(tester.widget<CollectionFilterRow>(filterRow).chips.take(2).map((chip) => chip.id), [
          'view',
          'contents',
        ]);
        final gutter = layout.screen.width >= Breakpoints.desktopSmall ? Spacing.lg : Spacing.md;
        final contentLeft = layout.screen.width - layout.width + gutter;
        final options = collectionGridSizeOptions(layout.width - gutter * 2);

        if (layout.screen.width < Breakpoints.desktopSmall) {
          expect(options.last.columns, 4);
        }

        for (final option in options) {
          provider.gridDensity.width = option.preferredWidth;
          await tester.pumpAndSettle();
          final grid = tester.widget<GridView>(find.byType(GridView));
          final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
          expect(delegate.crossAxisCount, option.columns);
          final cards = find.descendant(of: find.byType(ShelfCard), matching: find.byType(Card));
          final first = tester.getRect(cards.first);
          expect(first.left, closeTo(contentLeft, .001));
          expect(first.top - tester.getRect(find.byType(ShelvesFilterChips)).bottom, Spacing.sm);

          final row = cards
              .evaluate()
              .map((item) => tester.getRect(find.byWidget(item.widget)))
              .where((item) => item.top == first.top)
              .toList();

          expect(row.length, option.columns);
          expect(row.last.right, closeTo(layout.screen.width - gutter, .001));
          final spacing = layout.width - gutter * 2 >= Breakpoints.tablet ? 12 : 6;
          expect(delegate.crossAxisSpacing, spacing);

          for (var i = 1; i < row.length; i++) {
            expect(row[i].left - row[i - 1].right, closeTo(spacing, .001));
          }

          expect(tester.takeException(), isNull);
        }

        await tester.drag(find.byType(GridView), const Offset(0, -10000));
        await tester.pumpAndSettle();

        if (layout.screen.width < Breakpoints.desktopSmall) {
          expect(
            tester.getRect(find.byType(ShelfCard).last).bottom,
            lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
          );
        }

        provider.setViewMode(LibraryViewMode.list);
        await tester.pumpAndSettle();
        expect(tester.widget<CollectionFilterRow>(filterRow).chips.take(2).map((chip) => chip.id), [
          'view',
          'contents',
        ]);
        final firstShelf = find.byType(ShelfCard).first;
        final icon = find.descendant(of: firstShelf, matching: find.byType(Container)).first;
        expect(tester.getRect(icon).left, contentLeft);

        final list = find.descendant(of: find.byType(ShelvesPage), matching: find.byType(ListView)).last;
        await tester.drag(list, const Offset(0, -10000));
        await tester.pumpAndSettle();

        if (layout.screen.width < Breakpoints.desktopSmall) {
          expect(
            tester.getRect(find.byType(ShelfCard).last).bottom,
            lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
          );
        }

        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final layout in [
    (screen: 400.0, width: 400.0),
    (screen: 1200.0, width: 1200.0),
    (screen: 1200.0, width: 560.0),
  ]) {
    final width = layout.width;

    testWidgets('shelf view sheet applies real columns and retains density at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(layout.screen, 1000);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'library_grid_item_width': 200.0});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      final library = LibraryProvider(preferences: preferences);
      final store = createTestDataStore();

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        library.dispose();
        preferences.dispose();
        store.dispose();
      });

      await tester.pumpWidget(
        createTestPage(
          dataStore: store,
          libraryProvider: library,
          additionalProviders: [ChangeNotifierProvider.value(value: preferences)],
          screenSize: Size(layout.screen, 1000),
          page: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const ShelvesPage()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final chipsContext = tester.element(find.byType(ShelvesFilterChips));
      final provider = chipsContext.read<ShelvesProvider>();
      final books = chipsContext.read<LibraryProvider>();
      final gutter = layout.screen >= Breakpoints.desktopSmall ? Spacing.lg : Spacing.md;
      final options = collectionGridSizeOptions(width - gutter * 2);
      provider.gridDensity.width = options.last.preferredWidth;
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byTooltip('Change view mode'),
        200,
        scrollable: find.descendant(of: find.byType(ShelvesFilterChips), matching: find.byType(Scrollable)).first,
      );

      await tester.ensureVisible(find.byTooltip('Change view mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change view mode'));
      await tester.pumpAndSettle();
      expect(find.text('Small grid'), findsNothing);
      expect(find.text('Large grid'), findsNothing);
      final slider = find.byType(Slider);
      final sliderSemantics = tester.getSemantics(slider);
      expect(tester.widget<Slider>(slider).divisions, options.length - 1);
      sliderSemantics.owner!.performAction(sliderSemantics.id, SemanticsAction.focus);
      await tester.pumpAndSettle();

      for (final (index, option) in options.reversed.indexed) {
        if (index > 0) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }

        final label = '${option.columns} ${option.columns == 1 ? 'column' : 'columns'}';
        expect(tester.getSemantics(slider).getSemanticsData().value, label);
        expect(provider.gridDensity.width, option.preferredWidth);
        expect(books.gridDensity.width, 200);

        expect(
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          option.columns,
        );
      }

      final density = provider.gridDensity.width;
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      expect(provider.viewMode, LibraryViewMode.list);
      expect(books.viewMode, LibraryViewMode.grid);
      expect(find.text('Columns'), findsNothing);
      await tester.tap(find.text('Grid').last);
      await tester.pumpAndSettle();
      expect(provider.gridDensity.width, density);
      expect(find.text('Columns'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('View mode'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact shelf mosaics with missing images fit at enlarged text', (tester) async {
    for (var covers = 1; covers <= 4; covers++) {
      await tester.pumpWidget(
        createTestApp(
          screenSize: const Size(400, 1000),
          child: Theme(
            data: AppTheme.dark,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(400, 1000), textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 66,
                  height: 180,
                  child: ShelfCard(
                    shelf: buildTestShelf().copyWith(
                      bookCount: 999999,
                      coverPreviews: List.generate(
                        covers,
                        (i) => CoverPreview(bookId: 'book-$i', title: 'A long book title'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final previews = tester.widgetList<CoverImage>(find.byType(CoverImage));
      expect(previews, hasLength(covers));
      expect(previews.map((preview) => preview.fit), everyElement(BoxFit.cover));
      expect(tester.takeException(), isNull, reason: '$covers-cover mosaic');
    }
  });
}
