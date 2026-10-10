import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/shelves_page.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/shelves_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/book_grid_layout.dart';
import 'package:papyrus/widgets/shelves/shelf_card.dart';
import 'package:papyrus/widgets/shelves/shelves_filter_chips.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
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
        final search = tester.getRect(find.byType(TextField));
        final gutter = layout.screen.width >= Breakpoints.desktopSmall ? Spacing.lg : Spacing.md;
        final options = bookGridSizeOptions(layout.width - gutter * 2);

        if (layout.screen.width < Breakpoints.desktopSmall) {
          expect(options.last.columns, 4);
        }

        for (final option in options) {
          provider.setGridItemWidth(option.preferredWidth);
          await tester.pumpAndSettle();
          final grid = tester.widget<GridView>(find.byType(GridView));
          expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, option.columns);
          final cards = find.descendant(of: find.byType(ShelfCard), matching: find.byType(Card));
          final first = tester.getRect(cards.first);
          expect(first.left, closeTo(search.left, .001));
          expect(first.top - tester.getRect(find.byType(ShelvesFilterChips)).bottom, Spacing.sm);

          final row = cards
              .evaluate()
              .map((item) => tester.getRect(find.byWidget(item.widget)))
              .where((item) => item.top == first.top)
              .toList();

          expect(row.length, option.columns);
          expect(row.last.right, closeTo(layout.screen.width - gutter, .001));
          final spacing = bookGridLayout(layout.width - gutter * 2, itemWidth: option.preferredWidth).spacing;

          for (var i = 1; i < row.length; i++) {
            expect(row[i].left - row[i - 1].right, closeTo(spacing, .001));
          }

          expect(tester.takeException(), isNull);
        }

        provider.setViewMode(LibraryViewMode.list);
        await tester.pumpAndSettle();
        final firstShelf = find.byType(ShelfCard).first;
        final icon = find.descendant(of: firstShelf, matching: find.byType(Container)).first;
        expect(tester.getRect(icon).left, search.left);
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
      final store = createTestDataStore();

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      });

      await tester.pumpWidget(
        createTestPage(
          dataStore: store,
          screenSize: Size(layout.screen, 1000),
          page: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const ShelvesPage()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final provider = tester.element(find.byType(ShelvesFilterChips)).read<ShelvesProvider>();

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
      final gutter = layout.screen >= Breakpoints.desktopSmall ? Spacing.lg : Spacing.md;
      final options = bookGridSizeOptions(width - gutter * 2);

      for (final option in options) {
        final label = '${option.columns} ${option.columns == 1 ? 'column' : 'columns'}';
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected, isTrue);

        expect(
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          option.columns,
        );
      }

      final density = provider.gridItemWidth;
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      expect(provider.viewMode, LibraryViewMode.list);
      expect(find.text('Columns'), findsNothing);
      await tester.tap(find.text('Grid').last);
      await tester.pumpAndSettle();
      expect(provider.gridItemWidth, density);
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
      expect(tester.takeException(), isNull, reason: '$covers-cover mosaic');
    }
  });
}
