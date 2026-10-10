import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/providers/enums/library_sort_option.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/widgets/library/library_filter_chips.dart';
import 'package:papyrus/widgets/library/book_grid_layout.dart';

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

    testWidgets('renders the current filter, sort, and view categories', (tester) async {
      await pumpChips(tester);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text(LibrarySortOption.dateAddedNewest.label), findsOneWidget);
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

    testWidgets('shows active multi-select categories first with a count label', (tester) async {
      libraryProvider.setStatusFilters({LibraryReadingStatus.inProgress, LibraryReadingStatus.completed});
      await pumpChips(tester);
      expect(find.text('Status · 2'), findsOneWidget);
      expect(libraryProvider.activeFilterCount, 1);
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

    testWidgets('view selection sheet updates the shared view mode', (tester) async {
      await pumpChips(tester);
      await tester.tap(find.text(LibraryViewMode.grid.label));
      await tester.pumpAndSettle();
      expect(find.text('View mode'), findsOneWidget);
      await tester.tap(find.text(LibraryViewMode.list.label).last);
      await tester.pumpAndSettle();
      expect(libraryProvider.viewMode, LibraryViewMode.list);
    });

    testWidgets('column choices retain the selected density across list view', (tester) async {
      await pumpChips(tester);
      await tester.tap(find.text(LibraryViewMode.grid.label));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.text('6 columns'));
      await tester.pumpAndSettle();
      final selectedSize = libraryProvider.gridItemWidth;
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '6 columns')).selected, isTrue);
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      expect(find.text('Columns'), findsNothing);
      await tester.tap(find.text('Grid').last);
      await tester.pumpAndSettle();
      expect(libraryProvider.gridItemWidth, selectedSize);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '6 columns')).selected, isTrue);
    });

    for (final layout in [
      (screenWidth: 1800.0, contentWidth: 500.0, padding: 24.0, scale: 1.0),
      (screenWidth: 400.0, contentWidth: 400.0, padding: 16.0, scale: 2.0),
    ]) {
      testWidgets('column choices use content width ${layout.contentWidth} at text scale ${layout.scale}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(layout.screenWidth, 1000);
        addTearDown(tester.view.reset);

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
        final options = bookGridSizeOptions(layout.contentWidth - 2 * layout.padding);

        final choices = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => (chip.label as Text).data!.contains('column'));

        expect(choices.map((chip) => (chip.label as Text).data), [
          for (final option in options) '${option.columns} ${option.columns == 1 ? 'column' : 'columns'}',
        ]);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Clear all resets filters, sort, and view', (tester) async {
      libraryProvider.setStatusFilters({LibraryReadingStatus.inProgress});
      libraryProvider.setSortOption(LibrarySortOption.titleAZ);
      libraryProvider.setViewMode(LibraryViewMode.list);
      await pumpChips(tester);
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(libraryProvider.filters.isEmpty, isTrue);
      expect(libraryProvider.sortOption, LibrarySortOption.dateAddedNewest);
      expect(libraryProvider.viewMode, LibraryViewMode.grid);
    });
  });
}
