import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/providers/enums/library_sort_option.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/widgets/library/library_filter_chips.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('LibraryFilterChips', () {
    late LibraryProvider libraryProvider;

    setUp(() {
      libraryProvider = LibraryProvider();
    });

    tearDown(() {
      libraryProvider.dispose();
    });

    Widget buildChips() {
      return createTestApp(
        libraryProvider: libraryProvider,
        screenSize: const Size(1800, 800),
        child: const LibraryFilterChips(),
      );
    }

    Future<void> pumpChips(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildChips());
    }

    testWidgets('filter launcher has one button role and scales its label', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(320, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          createTestApp(
            libraryProvider: libraryProvider,
            child: const MediaQuery(
              data: MediaQueryData(size: Size(320, 720), textScaler: TextScaler.linear(4)),
              child: LibraryFilterChips(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final launcher = find.bySemanticsLabel('View mode: Grid');
        expect(launcher, findsOneWidget);
        expect(
          tester.getSemantics(launcher),
          isSemantics(
            isButton: true,
            hasCheckedState: false,
            hasTapAction: true,
            isFocusable: true,
          ),
        );
        final label = find.text('Grid');
        expect(MediaQuery.textScalerOf(tester.element(label)).scale(14), 56);
        expect(tester.getSize(find.byType(LibraryFilterChips)).height, greaterThan(48));
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(find.text('View mode'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('renders the current filter, sort, and view categories', (tester) async {
      await pumpChips(tester);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text(LibrarySortOption.lastRead.label), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Topic'), findsOneWidget);
      expect(find.text('Shelf'), findsOneWidget);
      expect(find.text(LibraryViewMode.grid.label), findsOneWidget);
    });

    testWidgets('uses a horizontal list with fixed height', (tester) async {
      await pumpChips(tester);
      final listView = tester.widget<ListView>(find.byType(ListView));

      final container = tester.widget<SizedBox>(
        find.ancestor(of: find.byType(AnimatedSwitcher), matching: find.byType(SizedBox)).first,
      );

      expect(listView.scrollDirection, Axis.horizontal);
      expect(container.height, 48);
    });

    testWidgets('keeps view mode before active multi-select categories', (tester) async {
      libraryProvider.setStatusFilters({LibraryReadingStatus.inProgress, LibraryReadingStatus.completed});
      await pumpChips(tester);
      expect(find.text('Status · 2'), findsOneWidget);
      expect(libraryProvider.activeFilterCount, 1);
      expect(tester.getRect(find.text('Grid')).left, lessThan(tester.getRect(find.text('Status · 2')).left));
      libraryProvider.setViewMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('List')).left, lessThan(tester.getRect(find.text('Status · 2')).left));
    });

    testWidgets('favorite selection sheet updates the shared filter model', (tester) async {
      await pumpChips(tester);
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('Favorite state'), findsOneWidget);
      await tester.tap(find.text('Favorites').last);
      await tester.pumpAndSettle();
      expect(libraryProvider.favoriteFilter, FavoriteFilter.favorites);
    });

    for (final category in ['Favorites', 'Format']) {
      testWidgets('$category short mobile sheet retains normal header spacing', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 693);
        addTearDown(tester.view.reset);
        final store = DataStore()..loadData(books: createTestBooks().take(2).toList());
        addTearDown(store.dispose);

        await tester.pumpWidget(
          createTestApp(
            libraryProvider: libraryProvider,
            dataStore: store,
            screenSize: const Size(400, 693),
            child: const LibraryFilterChips(),
          ),
        );

        await tester.scrollUntilVisible(find.text(category), 150, scrollable: find.byType(Scrollable));
        await Scrollable.ensureVisible(tester.element(find.text(category)), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(find.text(category));
        await tester.pumpAndSettle();
        final header = find.byKey(const Key('bottom-sheet-header'));
        final title = find.text(category == 'Format' ? 'Formats' : 'Favorite state');
        final handle = find.byType(BottomSheetHandle);
        expect(tester.getTopLeft(handle).dy - tester.getTopLeft(header).dy, Spacing.sm);
        expect(tester.getTopLeft(title).dy - tester.getBottomRight(handle).dy, Spacing.xs);
        expect(tester.getBottomRight(header).dy - tester.getBottomRight(title).dy, Spacing.sm);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shelves filter stays open when scrolling back to the top with momentum', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      final store = DataStore()
        ..loadData(
          shelves: List.generate(30, (index) => buildTestShelf(id: 'shelf-$index', name: 'Shelf $index')),
        );

      addTearDown(store.dispose);

      await tester.pumpWidget(
        createTestApp(
          libraryProvider: libraryProvider,
          dataStore: store,
          screenSize: const Size(400, 800),
          child: const LibraryFilterChips(),
        ),
      );

      await tester.scrollUntilVisible(find.text('Shelf'), 150, scrollable: find.byType(Scrollable));
      await Scrollable.ensureVisible(tester.element(find.text('Shelf')), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shelf'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(BottomSheetHandle), const Offset(0, -500));
      await tester.pumpAndSettle();

      final scrollable = find
          .descendant(of: find.byType(ExpandableBottomSheet), matching: find.byType(Scrollable))
          .first;

      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(100));
      position.jumpTo(100);
      await tester.pump();
      await tester.fling(scrollable, const Offset(0, 250), 4000);
      await tester.pumpAndSettle();
      expect(find.text('Shelves'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(position.pixels, 0);
      await tester.drag(find.byType(BottomSheetHandle), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text('Shelves'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('view selection sheet updates the shared view mode', (tester) async {
      await pumpChips(tester);
      await tester.tap(find.text(LibraryViewMode.grid.label));
      await tester.pumpAndSettle();
      expect(find.text('View mode'), findsOneWidget);
      await tester.tap(find.text(LibraryViewMode.list.label).last);
      await tester.pumpAndSettle();
      expect(libraryProvider.viewMode, LibraryViewMode.list);
    });

    testWidgets('dragging the column slider updates density and retains it across list view', (tester) async {
      await pumpChips(tester);
      await tester.tap(find.text(LibraryViewMode.grid.label));
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      final initialSize = libraryProvider.gridDensity.width;
      final bounds = tester.getRect(slider);
      await tester.drag(slider, Offset(bounds.width / 2 - Spacing.sm, 0));
      await tester.pumpAndSettle();
      final selectedSize = libraryProvider.gridDensity.width;
      final selectedStep = tester.widget<Slider>(slider);
      expect(selectedSize, lessThan(initialSize));
      expect(selectedStep.value, selectedStep.max);
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      expect(slider, findsNothing);
      await tester.tap(find.text('Grid').last);
      await tester.pumpAndSettle();
      expect(libraryProvider.gridDensity.width, selectedSize);
      expect(tester.widget<Slider>(slider).value, selectedStep.value);
    });

    for (final layout in [
      (screenWidth: 1800.0, contentWidth: 500.0, padding: 24.0, scale: 1.0),
      (screenWidth: 400.0, contentWidth: 400.0, padding: 16.0, scale: 2.0),
      (screenWidth: 1800.0, contentWidth: 150.0, padding: 24.0, scale: 1.0),
    ]) {
      testWidgets('column slider uses content width ${layout.contentWidth} at text scale ${layout.scale}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(layout.screenWidth, 1000);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          createTestApp(
            libraryProvider: libraryProvider,
            screenSize: Size(layout.screenWidth, 1000),
            child: MediaQuery(
              data: MediaQueryData(size: Size(layout.screenWidth, 1000), textScaler: TextScaler.linear(layout.scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: layout.contentWidth,
                  child: LibraryFilterChips(horizontalPadding: layout.padding),
                ),
              ),
            ),
          ),
        );

        await tester.scrollUntilVisible(find.text('Grid'), 300, scrollable: find.byType(Scrollable));
        await Scrollable.ensureVisible(tester.element(find.byTooltip('Change view mode')), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Grid'));
        await tester.pumpAndSettle();
        expect(find.text('View mode'), findsOneWidget);
        final options = collectionGridSizeOptions(layout.contentWidth - 2 * layout.padding);

        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.max, options.length - 1);
        expect(slider.divisions, options.length > 1 ? options.length - 1 : null);
        expect(slider.onChanged, options.length > 1 ? isNotNull : isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the open Books view sheet follows its grid pane width', (tester) async {
      const screen = Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.reset);
      final paneWidth = ValueNotifier(900.0);
      addTearDown(paneWidth.dispose);

      await tester.pumpWidget(
        createTestApp(
          libraryProvider: libraryProvider,
          screenSize: screen,
          child: ValueListenableBuilder(
            valueListenable: paneWidth,
            child: const LibraryFilterChips(horizontalPadding: 24),
            builder: (context, width, child) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      expect(tester.widget<Slider>(slider).divisions, collectionGridSizeOptions(900 - 48).length - 1);
      paneWidth.value = 400;
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).divisions, collectionGridSizeOptions(400 - 48).length - 1);
    });

    testWidgets('Clear all leads the row and resets filters, sort, and view', (tester) async {
      libraryProvider.setStatusFilters({LibraryReadingStatus.inProgress});
      libraryProvider.setSortOption(LibrarySortOption.dateAddedNewest);
      libraryProvider.setViewMode(LibraryViewMode.list);
      await pumpChips(tester);
      final clearAll = find.widgetWithText(TextButton, 'Clear all');
      expect(tester.getRect(clearAll).left, lessThan(tester.getRect(find.text('List')).left));
      expect(find.descendant(of: clearAll, matching: find.byIcon(Icons.filter_alt_off_outlined)), findsOneWidget);
      await tester.tap(clearAll);
      await tester.pumpAndSettle();
      expect(libraryProvider.filters.isEmpty, isTrue);
      expect(libraryProvider.sortOption, LibrarySortOption.lastRead);
      expect(libraryProvider.viewMode, LibraryViewMode.grid);
      expect(find.text('Clear all'), findsNothing);
    });
  });
}
