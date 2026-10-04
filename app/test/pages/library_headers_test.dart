import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/annotations_page.dart';
import 'package:papyrus/pages/bookmarks_page.dart';
import 'package:papyrus/pages/catalogs_page.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/pages/notes_page.dart';
import 'package:papyrus/pages/shelves_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';
import '../opds/catalog_store_test.dart' show MemorySecrets;

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    testWidgets('shelf and catalog empty states match colors, typography and action size in ${theme.brightness}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = createTestDataStore(books: [], shelves: []);
      final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
        ..setScope('local--guest');
      final downloads = OpdsDownloads(captureImport: () => throw StateError('Unexpected import'));
      final httpClient = OpdsHttpClient();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        catalogs.dispose();
        downloads.dispose();
      });
      await tester.pumpWidget(
        createTestPage(
          dataStore: store,
          screenSize: const Size(1200, 1000),
          additionalProviders: [
            ChangeNotifierProvider.value(value: catalogs),
            ChangeNotifierProvider.value(value: downloads),
            Provider.value(value: httpClient),
          ],
          page: Theme(
            data: theme,
            child: const Row(
              children: [
                Expanded(child: ShelvesPage()),
                Expanded(child: CatalogsPage()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shelfAction = find.ancestor(of: find.text('Create shelf'), matching: find.byType(EmptyStateAction));
      final catalogAction = find.ancestor(of: find.text('Add catalog'), matching: find.byType(EmptyStateAction));
      final shelfState = find.ancestor(of: shelfAction, matching: find.byType(EmptyState));
      final catalogState = find.ancestor(of: catalogAction, matching: find.byType(EmptyState));
      expect(shelfState, findsOneWidget);
      expect(catalogState, findsOneWidget);
      final shelfIcon = tester.widget<Icon>(find.descendant(of: shelfState, matching: find.byIcon(Icons.shelves)));
      final catalogIcon = tester.widget<Icon>(
        find.descendant(of: catalogState, matching: find.byIcon(Icons.local_library_outlined)),
      );
      expect(shelfIcon.color, catalogIcon.color);
      expect(shelfIcon.size, catalogIcon.size);
      expect(
        tester.widget<Text>(find.text('No shelves yet')).style,
        tester.widget<Text>(find.text('No catalogs yet')).style,
      );
      final shelfSubtitle = tester.widget<Text>(find.text('Create shelves to organize your books into collections'));
      final catalogSubtitle = tester.widget<Text>(
        find.text('Connect an OPDS catalog to explore its collection and add books to your library.'),
      );
      expect(shelfSubtitle.style, catalogSubtitle.style);
      expect(tester.getSize(shelfAction), tester.getSize(catalogAction));
      expect(tester.getSize(shelfAction).height, greaterThanOrEqualTo(50));
      for (final action in [shelfAction, catalogAction]) {
        expect(find.descendant(of: action, matching: find.byIcon(Icons.add)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  const pages = <String, Widget>{
    'Books': LibraryPage(),
    'Shelves': ShelvesPage(),
    'Bookmarks': BookmarksPage(),
    'Annotations': AnnotationsPage(),
    'Notes': NotesPage(),
  };

  for (final entry in pages.entries) {
    for (final layout in [
      (screen: const Size(400, 1000), pageWidth: 400.0, scale: 1.0),
      (screen: const Size(360, 1000), pageWidth: 360.0, scale: 2.0),
      (screen: const Size(840, 1000), pageWidth: 560.0, scale: 2.0),
      (screen: const Size(1200, 1000), pageWidth: 920.0, scale: 1.0),
    ]) {
      testWidgets('${entry.key} uses a compact collection layout at ${layout.screen.width}, scale ${layout.scale}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.screen;
        addTearDown(tester.view.reset);
        final store = createTestDataStore(books: [], shelves: []);
        addTearDown(store.dispose);

        await tester.pumpWidget(
          createTestPage(
            dataStore: store,
            screenSize: layout.screen,
            page: MediaQuery(
              data: MediaQueryData(size: layout.screen, textScaler: TextScaler.linear(layout.scale)),
              child: Theme(
                data: layout.scale == 1 ? AppTheme.dark : AppTheme.eink,
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(width: layout.pageWidth, child: entry.value),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(entry.key), findsNothing);
        expect(find.byType(LibraryPageHeader), findsNothing);

        if (layout.screen.width < 840) {
          expect(tester.getTopLeft(find.byType(LibraryMobileToolbar)).dy, 16);
          expect(tester.getTopLeft(find.byType(TextField)).dx, tester.getTopLeft(find.byType(LibraryMobileToolbar)).dx);
          expect(
            find.descendant(of: find.byType(TextField), matching: find.byTooltip('Library sections')),
            findsOneWidget,
          );
          expect(tester.getCenter(find.byTooltip('Library sections')).dy, tester.getCenter(find.byType(TextField)).dy);
          await tester.tap(find.byTooltip('Library sections'));
          await tester.pumpAndSettle();
          expect(find.byType(Drawer), findsOneWidget);
        } else {
          expect(tester.getTopLeft(find.byType(LibraryToolbar)).dy, 24);
          if (layout.scale == 1 && (entry.key == 'Books' || entry.key == 'Shelves')) {
            expect(tester.getCenter(find.byType(TextField)).dy, tester.getCenter(find.byType(LibraryAddButton)).dy);
          }
          if (entry.key == 'Shelves') {
            await tester.tap(find.text('Add shelf'));
            await tester.pumpAndSettle();
            expect(find.text('Shelf name'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }
}
