import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/pages/annotations_page.dart';
import 'package:papyrus/pages/bookmarks_page.dart';
import 'package:papyrus/pages/catalogs_page.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/pages/notes_page.dart';
import 'package:papyrus/pages/shelves_page.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/library_drawer.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:papyrus/widgets/shell/nav_item_count.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_helpers.dart';
import '../../opds/catalog_store_test.dart' show MemorySecrets;

void main() {
  const sections = [
    (path: '/library', label: 'Books', page: LibraryPage()),
    (path: '/library/shelves', label: 'Shelves', page: ShelvesPage()),
    (path: '/library/catalogs', label: 'Catalogs', page: CatalogsPage()),
    (path: '/library/bookmarks', label: 'Bookmarks', page: BookmarksPage()),
    (path: '/library/annotations', label: 'Annotations', page: AnnotationsPage()),
    (path: '/library/notes', label: 'Notes', page: NotesPage()),
  ];
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final layout in [(width: 400.0, height: 850.0, scale: 1.0), (width: 320.0, height: 568.0, scale: 2.0)]) {
      testWidgets(
        'all Library pages share their drawer at ${layout.width}, scale ${layout.scale}, ${theme.brightness}',
        (tester) async {
          tester.view.physicalSize = Size(layout.width, layout.height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final catalogs = OpdsCatalogs(
            OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()),
          )..setScope('guest');
          await catalogs.save(
            OpdsCatalog(id: 'one', name: 'Sample catalog', uri: Uri.parse('https://catalog.test/feed')),
          );
          final store = createTestDataStore(books: createTestBooks().take(1).toList(), shelves: []);
          final library = LibraryProvider();
          final downloads = OpdsDownloads(captureImport: () => throw StateError('Unexpected import'));
          final router = GoRouter(
            initialLocation: '/library/catalogs',
            routes: [
              ShellRoute(
                builder: (_, _, child) => AdaptiveAppShell(child: child),
                routes: [for (final section in sections) GoRoute(path: section.path, builder: (_, _) => section.page)],
              ),
            ],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
            catalogs.dispose();
            store.dispose();
            library.dispose();
            downloads.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: store),
                ChangeNotifierProvider.value(value: library),
                ChangeNotifierProvider.value(value: catalogs),
                ChangeNotifierProvider.value(value: downloads),
                Provider(create: (_) => OpdsHttpClient()),
              ],
              child: MaterialApp.router(
                theme: theme,
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(layout.scale)),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Every page opens the shell drawer, covering the bottom navigation.
          // Follow real drawer links through every page and back to Catalogs.
          final journey = [sections[2], ...sections.where((section) => section.label != 'Catalogs'), sections[2]];
          for (var index = 0; index < journey.length; index++) {
            final section = journey[index];
            expect(router.routeInformationProvider.value.uri.path, section.path);
            if (theme.brightness == Brightness.dark && section.label == 'Books') {
              await tester.dragFrom(Offset(1, layout.height / 2), const Offset(280, 0));
            } else {
              await tester.tap(find.byTooltip('Library sections'));
            }
            await tester.pumpAndSettle();
            final drawer = find.byType(Drawer);
            expect(drawer, findsOneWidget);
            expect(tester.getSize(drawer).height, layout.height);
            expect(find.ancestor(of: drawer, matching: find.byType(LibraryDrawer)), findsOneWidget);
            final scrollable = find.descendant(of: drawer, matching: find.byType(Scrollable));
            await tester.drag(scrollable, const Offset(0, 2000));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<NavItemCount>(find.descendant(of: drawer, matching: find.byType(NavItemCount)))
                  .map((badge) => badge.count),
              [1, 1],
            );
            expect(
              tester.widget<Text>(find.descendant(of: drawer, matching: find.text('Library'))).style?.fontWeight,
              FontWeight.bold,
            );
            expect(tester.takeException(), isNull);
            final selected = find.descendant(of: drawer, matching: find.widgetWithText(ListTile, section.label));
            await tester.scrollUntilVisible(selected, 120, scrollable: scrollable);
            await tester.ensureVisible(selected);
            await tester.pumpAndSettle();
            expect(tester.widget<ListTile>(selected).selected, isTrue);
            if (index + 1 < journey.length) {
              await tester.drag(scrollable, const Offset(0, 2000));
              await tester.pumpAndSettle();
              final target = find.descendant(
                of: drawer,
                matching: find.widgetWithText(ListTile, journey[index + 1].label),
              );
              await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              await tester.tap(target);
              await tester.pumpAndSettle();
              expect(find.byType(Drawer), findsNothing);
            }
          }
        },
      );
    }
  }
}
