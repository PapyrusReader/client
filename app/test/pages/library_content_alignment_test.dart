import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/providers/acquisition_downloads_provider.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_card.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_list_item.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/library/book_grid_layout.dart';
import 'package:papyrus/widgets/library/book_list_item.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/library/library_filter_chips.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final layout in [
      (screen: const Size(320, 1000), pageWidth: 320.0, scale: 1.0),
      (screen: const Size(400, 1000), pageWidth: 400.0, scale: 1.0),
      (screen: const Size(320, 1000), pageWidth: 320.0, scale: 2.0),
      (screen: const Size(840, 1000), pageWidth: 560.0, scale: 1.0),
      (screen: const Size(1200, 1000), pageWidth: 920.0, scale: 1.0),
      (screen: const Size(1200, 1000), pageWidth: 920.0, scale: 2.0),
    ]) {
      testWidgets('visible books align with search at ${layout.screen.width}/${layout.pageWidth}, '
          'scale ${layout.scale}, ${theme.brightness}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.screen;
        addTearDown(tester.view.reset);
        final provider = LibraryProvider();
        final downloads = _Downloads();
        final store = createTestDataStore(
          books: List.generate(
            12,
            (i) => Book(
              id: 'book-$i',
              title: 'Book $i with a long title',
              author: 'An author',
              isPhysical: i.isEven,
              addedAt: DateTime(2026).add(Duration(days: i)),
            ),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          provider.dispose();
          downloads.dispose();
          store.dispose();
        });
        await tester.pumpWidget(
          createTestPage(
            libraryProvider: provider,
            dataStore: store,
            screenSize: layout.screen,
            additionalProviders: [ChangeNotifierProvider<AcquisitionDownloadsProvider>.value(value: downloads)],
            page: MediaQuery(
              data: MediaQueryData(size: layout.screen, textScaler: TextScaler.linear(layout.scale)),
              child: Theme(
                data: theme,
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(width: layout.pageWidth, child: const LibraryPage()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final search = tester.getRect(find.byType(TextField));
        final mobile = layout.screen.width < 840;
        final toolbar = tester.getRect(find.byType(mobile ? LibraryMobileToolbar : LibraryToolbar));
        final gutter = mobile ? 16.0 : 24.0;
        expect(search.left, closeTo(layout.screen.width - layout.pageWidth + gutter, .001));
        expect(toolbar.left, closeTo(search.left, .001));
        if (mobile) {
          expect(search.right, closeTo(toolbar.right, .001));
          expect(
            find.descendant(of: find.byType(TextField), matching: find.byTooltip('Library sections')),
            findsOneWidget,
          );
        }

        // Check the painted covers, not just the grid slots: themed Card margins
        // previously made slot-only geometry tests pass despite visible drift.
        for (final option in bookGridSizeOptions(layout.pageWidth - gutter * 2)) {
          provider.setGridItemWidth(option.preferredWidth);
          await tester.pumpAndSettle();
          final covers = find.descendant(of: find.byType(BookCard), matching: find.byType(CoverImage));
          final first = tester.getRect(covers.first);
          expect(first.left, closeTo(search.left, .001), reason: '${option.columns} columns');
          expect(
            first.top - tester.getRect(find.byType(LibraryFilterChips)).bottom,
            closeTo(Spacing.sm, .001),
            reason: 'Grid covers need the same top inset as list thumbnails at every density',
          );
          final row = covers
              .evaluate()
              .map((element) => tester.getRect(find.byWidget(element.widget)))
              .where((rect) => (rect.top - first.top).abs() < .001)
              .toList();
          expect(row.length, option.columns);
          expect(row.last.right, closeTo(toolbar.right, .001));
          final spacing = bookGridLayout(layout.pageWidth - gutter * 2, itemWidth: option.preferredWidth).spacing;
          for (var i = 1; i < row.length; i++) {
            expect(row[i].left - row[i - 1].right, closeTo(spacing, .001));
          }
          expect(tester.takeException(), isNull);
        }

        // Orphan downloads must use the same gutters in grid and list mode.
        await tester.drag(find.byType(GridView), const Offset(0, -10000));
        await tester.pumpAndSettle();
        final placeholderSurface = find.descendant(
          of: find.byType(AcquisitionPlaceholderCard),
          matching: find.byType(InkWell),
        );
        expect(tester.getRect(placeholderSurface.first).left, closeTo(search.left, .001));

        provider.setViewMode(LibraryViewMode.list);
        await tester.pumpAndSettle();
        final firstRow = find.byType(BookListItem).first;
        final firstCover = find.descendant(of: firstRow, matching: find.byType(CoverImage));
        final rowContent = find.descendant(of: firstRow, matching: find.byType(Row)).first;
        expect(tester.getRect(firstCover).left, closeTo(search.left, .001));
        expect(
          tester.getRect(rowContent).top - tester.getRect(find.byType(LibraryFilterChips)).bottom,
          closeTo(Spacing.sm, .001),
          reason: 'List rows retain their own vertical padding',
        );
        expect(tester.getRect(firstRow).right, closeTo(toolbar.right, .001));
        await tester.drag(
          find.descendant(of: find.byType(LibraryPage), matching: find.byType(ListView)).last,
          const Offset(0, -10000),
        );
        await tester.pumpAndSettle();
        final placeholderCover = find.descendant(
          of: find.byType(AcquisitionPlaceholderListItem),
          matching: find.byType(ClipRRect),
        );
        expect(tester.getRect(placeholderCover).left, closeTo(search.left, .001));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Downloads extends AcquisitionDownloadsProvider {
  _Downloads() : super(pollingInterval: Duration.zero);

  @override
  List<AcquisitionJob> get jobs => [
    AcquisitionJob(
      id: 'pending',
      endpointId: null,
      ruleId: null,
      bookId: null,
      title: 'Waiting for synchronization',
      status: AcquisitionJobStatus.downloading,
      clientReference: null,
      clientHash: null,
      clientState: null,
      progressBasisPoints: 4200,
      downloadedBytes: 420,
      totalBytes: 1000,
      downloadSpeedBytesPerSecond: null,
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
    ),
  ];
}
