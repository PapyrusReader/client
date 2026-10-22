import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/widgets/library/online_books_header.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/search/library_search_bar.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('navigation stays aligned in ${theme.brightness}, $platform, text scale $scale', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(400, 850);
          addTearDown(tester.view.reset);
          final book = buildTestBook(title: "Alice's Adventures in Wonderland");
          final store = DataStore()..loadData(books: [book]);
          addTearDown(store.dispose);
          final library = LibraryProvider();
          addTearDown(library.dispose);

          Widget app(Widget page) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: store),
              ChangeNotifierProvider.value(value: library),
            ],
            child: MaterialApp(
              theme: theme.copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24),
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: page,
            ),
          );

          await tester.pumpWidget(
            app(
              Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LibraryMobileToolbar(
                      onMenuPressed: () {},
                      search: const LibrarySearchBar(),
                    ),
                  ),
                ),
              ),
            ),
          );

          final menuCenter = tester.getCenter(find.byIcon(Icons.menu));
          final menuSize = tester.getSize(find.byIcon(Icons.menu));
          expect(tester.getSize(find.byTooltip('Library sections')), const Size(48, 48));
          await tester.pumpWidget(app(BookDetailsPage(id: book.id)));
          await tester.pumpAndSettle();
          final back = find.byType(BackButtonIcon);
          expect(tester.getCenter(back), menuCenter);
          expect(tester.getSize(back), menuSize);
          expect(tester.getTopLeft(find.byType(CoverImagePreview)).dy, switch (scale) {
            1.0 => 104,
            1.5 => 108,
            _ => 120,
          });
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            app(
              Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LibraryMobileToolbar(onMenuPressed: () {}),
                  ),
                ),
              ),
            ),
          );

          expect(tester.getCenter(find.byIcon(Icons.menu)), menuCenter);

          await tester.pumpWidget(
            app(
              Scaffold(
                body: SafeArea(
                  child: LibraryPageHeader(
                    compact: true,
                    title: 'Catalog',
                    leading: BackButton(onPressed: () {}),
                  ),
                ),
              ),
            ),
          );

          expect(tester.getCenter(find.byType(BackButtonIcon)), menuCenter);
          expect(tester.takeException(), isNull);
          var backCalls = 0;
          await tester.pumpWidget(
            app(LibraryPage(shelf: buildTestShelf(), onBack: () => backCalls += 1, onEditShelf: () {})),
          );

          await tester.pumpAndSettle();
          expect(tester.getCenter(find.byTooltip('Back to shelves')), menuCenter);
          await tester.tap(find.byTooltip('Back to shelves'));
          expect(backCalls, 1);
          expect(tester.takeException(), isNull);
          final search = TextEditingController();
          addTearDown(search.dispose);

          await tester.pumpWidget(
            app(
              Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OnlineBooksHeader(
                      controller: search,
                      autofocus: false,
                      isSearching: false,
                      onBack: () => backCalls += 1,
                      onSearch: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(tester.getCenter(find.byTooltip('Back')), menuCenter);
          await tester.tap(find.byTooltip('Back'));
          expect(backCalls, 2);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
