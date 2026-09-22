import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_library.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/opds/opds_feed_view.dart';
import 'package:papyrus/widgets/opds/opds_publication_details.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final catalog = OpdsCatalog(id: 'c', name: 'Catalog', uri: Uri.parse('https://books.test/feed'));
  final epub = OpdsLink(
    uri: Uri.parse('https://books.test/book.epub'),
    type: 'application/epub+zip',
    title: 'EPUB (no images, older E-readers)',
    rels: ['download'],
  );
  final pdf = OpdsLink(uri: Uri.parse('https://books.test/book.pdf'), type: 'application/pdf', rels: ['download']);
  final publication = OpdsPublication(id: 'one', title: 'A book', links: [epub, pdf]);
  final book = Book(id: 'local', title: 'A book', author: 'Author', addedAt: DateTime(2026));
  late DataStore store;
  late OpdsLibrary library;
  late OpdsDownloads downloads;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = DataStore();
    await store.waitUntilLoaded();
    store.replaceBooksFromSync([book]);
    library = OpdsLibrary(prefs, dataStore: store)..setScope('guest');
    await library.record(library.capture(catalog, publication, epub)!, book.id);
    library.dispose();
    library = OpdsLibrary(prefs, dataStore: store)..setScope('guest');
    downloads = OpdsDownloads(library: library, captureImport: () => throw StateError('Must not import'));
  });
  tearDown(() {
    downloads.dispose();
    library.dispose();
    store.dispose();
  });

  for (final (width, scale) in [(360.0, 1.0), (424.0, 1.0), (360.0, 2.0)]) {
    testWidgets('restored ownership opens local book and updates details/options after deletion at $width / $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/catalog',
        routes: [
          GoRoute(
            path: '/catalog',
            builder: (_, _) => Scaffold(
              body: OpdsPublicationDetails(
                catalog: catalog,
                publication: publication,
                httpClient: OpdsHttpClient(),
                downloads: downloads,
                onDownload: (_) => throw StateError('Already imported'),
                onNavigate: (_) {},
              ),
            ),
          ),
          GoRoute(
            path: '/library/details/:id',
            builder: (_, state) => Scaffold(body: Text('Local ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.eink,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('In library'), findsNothing);
      expect(find.text('Open book'), findsOneWidget);
      expect(find.text('Add to library'), findsNothing);
      await tester.tap(find.text('Download options'));
      await tester.pumpAndSettle();
      final sheetOpen = find.descendant(of: find.byType(BottomSheet), matching: find.text('Open book'));
      expect(sheetOpen, findsOneWidget);
      final formatRect = tester.getRect(find.text('EPUB'));
      final detailRect = tester.getRect(find.text(epub.title!));
      final openRect = tester.getRect(find.ancestor(of: sheetOpen, matching: find.byType(FilledButton)));
      if (scale == 1) {
        expect(openRect.center.dy, closeTo((formatRect.top + detailRect.bottom) / 2, 0.1));
        expect(openRect.left, greaterThan(detailRect.right));
      } else {
        expect(openRect.top, greaterThan(detailRect.bottom));
      }
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Download EPUB'), findsNothing);
      await tester.tap(sheetOpen);
      await tester.pumpAndSettle();
      expect(find.text('Local local'), findsOneWidget);
      router.go('/catalog');
      await tester.pumpAndSettle();
      // A completed job must not override a later deletion from the real library.
      await downloads.start(catalog, publication, epub);
      store.replaceBooksFromSync([]);
      await tester.pumpAndSettle();
      expect(find.text('In library'), findsNothing);
      expect(find.text('Add to library'), findsOneWidget);
      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(find.text('Download EPUB'), findsOneWidget);
      expect(find.text('Open book'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final grid in [true, false]) {
    testWidgets('publication ${grid ? 'grid' : 'list'} distinguishes owned and other editions', (tester) async {
      final feed = OpdsFeed(
        uri: catalog.uri,
        title: 'Books',
        publications: [
          publication,
          OpdsPublication(id: 'another-edition', title: 'A book', links: [epub]),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.eink,
          home: Scaffold(
            body: AnimatedBuilder(
              animation: downloads,
              builder: (_, _) => OpdsFeedView(
                catalog: catalog,
                feed: feed,
                httpClient: OpdsHttpClient(),
                onNavigate: (_) {},
                onOpenPublication: (_) {},
                onRefresh: () {},
                isGridView: grid,
                onViewChanged: (_) {},
                onPage: (_) {},
                libraryBookId: (entry) => downloads.libraryBookId(catalog, entry),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('In library'), findsOneWidget);
      store.replaceBooksFromSync([]);
      await tester.pumpAndSettle();
      expect(find.textContaining('In library'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
