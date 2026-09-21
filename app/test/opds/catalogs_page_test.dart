import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/pages/catalogs_page.dart';
import 'package:papyrus/pages/catalog_book_page.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_store_test.dart' show MemorySecrets;
import 'relay_fixture_client.dart';

class _WidgetCatalogStore extends OpdsCatalogStore {
  _WidgetCatalogStore(super.prefs) : super(secrets: MemorySecrets());
  String? saveFailure;
  String? removeFailure;
  String? loadFailure;

  @override
  List<OpdsCatalog> load(String scope) {
    if (loadFailure != null) throw OpdsException(loadFailure!);
    return super.load(scope);
  }

  @override
  Future<void> save(String scope, OpdsCatalog catalog, {OpdsCredentials? credentials, bool clearCredentials = false}) {
    if (saveFailure != null) throw OpdsException(saveFailure!);
    return super.save(scope, catalog, credentials: credentials, clearCredentials: clearCredentials);
  }

  @override
  Future<void> remove(String scope, String id) {
    if (removeFailure != null) throw OpdsException(removeFailure!);
    return super.remove(scope, id);
  }
}

class _CatalogPageHarness {
  _CatalogPageHarness(this.store, this.catalogs);
  final _WidgetCatalogStore store;
  final OpdsCatalogs catalogs;
  final requests = <Uri>[];
  int importAttempts = 0;
  late final OpdsDownloads downloads;
  late final GoRouter router;

  static Future<_CatalogPageHarness> mount(
    WidgetTester tester,
    http.Response Function(Uri uri) respond, {
    String initialLocation = '/library/catalogs/one',
  }) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = _WidgetCatalogStore(await SharedPreferences.getInstance());
    await store.save(
      'local--guest',
      OpdsCatalog(id: 'one', name: 'My catalog', uri: Uri.parse('https://books.test/feed')),
    );
    final catalogs = OpdsCatalogs(store)..setScope('local--guest');
    final harness = _CatalogPageHarness(store, catalogs);
    final gateway = OpdsHttpClient(
      clientFactory: () => MockRelayClient((request) async {
        harness.requests.add(request.url);
        return respond(request.url);
      }),
    );
    harness.downloads = OpdsDownloads(
      httpClient: gateway,
      captureImport: () {
        harness.importAttempts++;
        throw StateError('This widget test must not start an import');
      },
    );
    Widget page(GoRouterState state) => CatalogsPage(
      catalogId: state.pathParameters['catalogId'],
      feedUri: state.uri.queryParameters['feed'] == null ? null : Uri.parse(state.uri.queryParameters['feed']!),
      query: state.uri.queryParameters['q'] ?? '',
    );
    harness.router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/library/catalogs',
          builder: (_, _) => const CatalogsPage(),
          routes: [
            GoRoute(path: ':catalogId', builder: (_, state) => page(state), routes: [catalogBookRoute()]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: catalogs),
          ChangeNotifierProvider.value(value: harness.downloads),
          Provider.value(value: gateway),
        ],
        child: MaterialApp.router(
          theme: AppTheme.eink,
          routerConfig: harness.router,
          builder: (_, child) => AppMotionScope(reduceAnimations: true, child: Scaffold(body: child!)),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.router.dispose();
      harness.catalogs.dispose();
      harness.downloads.dispose();
    });
    await _settleNetwork(tester);
    return harness;
  }
}

Future<void> _settleNetwork(WidgetTester tester) async {
  // A deep link loads its source feed and then its publication document.
  for (var hop = 0; hop < 3; hop++) {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pumpAndSettle();
}

http.Response _feedResponse(
  String title, {
  List<Map<String, dynamic>> publications = const [],
  List<Map<String, dynamic>> links = const [],
}) => http.Response(
  jsonEncode({
    'metadata': {'title': title},
    'publications': publications,
    'links': links,
  }),
  200,
  headers: {'content-type': 'application/opds+json'},
);

Map<String, dynamic> _book() => {
  'metadata': {'identifier': 'book-one', 'title': 'A book', 'author': 'An author'},
  'links': [
    {'rel': 'download', 'href': '/book.epub', 'type': 'application/epub+zip'},
  ],
};

void main() {
  testWidgets('mobile catalog home uses a FAB and keeps Downloads in the title row', (tester) async {
    await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books'), initialLocation: '/library/catalogs');
    tester.view.physicalSize = const Size(424, 951);
    await _settleNetwork(tester);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add catalog'), findsNothing);
    expect(tester.getTopLeft(find.byTooltip('Downloads')).dy, lessThan(tester.getBottomLeft(find.text('Catalogs')).dy));
    await tester.tap(find.byTooltip('Add catalog'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key('opds-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the last mobile source scrolls above the Add catalog FAB', (tester) async {
    final harness = await _CatalogPageHarness.mount(
      tester,
      (_) => _feedResponse('Books'),
      initialLocation: '/library/catalogs',
    );
    for (var index = 0; index < 12; index++) {
      await harness.store.save(
        'local--guest',
        OpdsCatalog(id: 'source-$index', name: 'Source $index', uri: Uri.parse('https://books.test/$index')),
      );
    }
    harness.catalogs.reload();
    tester.view.physicalSize = const Size(360, 640);
    await _settleNetwork(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.byTooltip('Catalog options').last).dy,
      lessThan(tester.getTopLeft(find.byType(FloatingActionButton)).dy),
    );
    await tester.tap(find.byTooltip('Catalog options').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone header keeps actions together and embeds search submission', (tester) async {
    await _CatalogPageHarness.mount(
      tester,
      (_) => _feedResponse('Pride and Prejudice by Jane Austen', publications: [_book()]),
    );
    tester.view.physicalSize = const Size(424, 951);
    await _settleNetwork(tester);
    final heading = tester.getRect(find.text('My catalog'));
    final downloads = tester.getRect(find.byTooltip('Downloads'));
    expect(downloads.top, lessThan(heading.bottom));
    expect(find.byTooltip('Catalog home'), findsNothing);
    expect(find.text('books.test'), findsNothing);
    final divider = tester.getRect(find.byKey(const Key('catalog-header-divider')));
    expect(divider.left, 0);
    expect(divider.width, 424);
    expect(divider.top, greaterThan(heading.bottom));
    final field = tester.getRect(find.byType(TextField));
    expect(field.contains(tester.getCenter(find.byTooltip('Search catalog'))), isTrue);
    expect(tester.getTopLeft(find.text('A book')).dy, lessThan(560));
    await tester.tap(find.byTooltip('Edit catalog'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('catalog sources use flat rows and edit in a bottom sheet', (tester) async {
    await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books'), initialLocation: '/library/catalogs');
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Card), findsNothing);
    await tester.tap(find.text('Add catalog').first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('publication opens a routed page instead of a modal', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books', publications: [_book()]));
    await tester.tap(find.text('A book'));
    await _settleNetwork(tester);
    expect(harness.router.routeInformationProvider.value.uri.path, '/library/catalogs/one/book');
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add to library'), findsOneWidget);
  });

  testWidgets('a direct book URL resolves metadata and missing publications can recover', (tester) async {
    var available = false;
    final location = Uri(
      path: '/library/catalogs/one/book',
      queryParameters: {
        'feed': 'https://books.test/search?q=tea%20%26%20coffee',
        'publication': 'urn:book/one?edition=2',
        'q': 'tea & coffee',
      },
    ).toString();
    final harness = await _CatalogPageHarness.mount(tester, (uri) {
      if (uri.path == '/detail') {
        return http.Response(
          jsonEncode({
            'metadata': {
              'identifier': 'urn:book/one?edition=2',
              'title': 'Full title',
              'description': 'Complete description.',
            },
            'links': [
              {'rel': 'download', 'href': '/book.epub', 'type': 'application/epub+zip'},
            ],
          }),
          200,
          headers: {'content-type': 'application/opds-publication+json'},
        );
      }
      return _feedResponse(
        'Search results',
        publications: available
            ? [
                {
                  'metadata': {'identifier': 'urn:book/one?edition=2', 'title': 'Preview'},
                  'links': [
                    {'rel': 'self', 'href': '/detail', 'type': 'application/opds-publication+json'},
                  ],
                },
              ]
            : [],
      );
    }, initialLocation: location);
    expect(find.text('Book unavailable'), findsOneWidget);
    available = true;
    await tester.tap(find.text('Retry'));
    await _settleNetwork(tester);
    expect(
      find.text('Full title'),
      findsOneWidget,
      reason: '${harness.requests}; ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
    );
    expect(find.text('Complete description.'), findsOneWidget);
    expect(harness.requests.last.path, '/detail');
    expect(find.text('Add to library'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to catalog'));
    await _settleNetwork(tester);
    expect(harness.router.routeInformationProvider.value.uri.queryParameters['q'], 'tea & coffee');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'tea & coffee');
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from a book keeps the feed position and list view', (tester) async {
    final harness = await _CatalogPageHarness.mount(
      tester,
      (_) => _feedResponse(
        'Books',
        publications: [
          for (var index = 0; index < 40; index++)
            {
              'metadata': {'identifier': 'book-$index', 'title': 'Book $index'},
              'links': [
                {'rel': 'download', 'href': '/$index.epub', 'type': 'application/epub+zip'},
              ],
            },
        ],
      ),
    );
    await tester.tap(find.byIcon(Icons.view_list));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Book 20'),
      500,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    final y = tester.getTopLeft(find.text('Book 20')).dy;
    final requests = harness.requests.length;
    await tester.tap(find.text('Book 20'));
    await _settleNetwork(tester);
    await tester.tap(find.byTooltip('Back to catalog'));
    await _settleNetwork(tester);
    expect(tester.getTopLeft(find.text('Book 20')).dy, closeTo(y, 1));
    expect(harness.requests.length, requests, reason: 'Returning should not reload the retained source feed.');
    expect(find.byType(SliverGrid), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book unavailable retries a transient catalog storage failure', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books', publications: [_book()]));
    await tester.tap(find.text('A book'));
    await _settleNetwork(tester);
    harness.store.loadFailure = 'Could not read saved catalogs.';
    harness.catalogs.reload();
    await _settleNetwork(tester);
    expect(find.text('Book unavailable'), findsOneWidget);
    harness.store.loadFailure = null;
    await tester.tap(find.text('Retry'));
    await _settleNetwork(tester);
    expect(find.text('Add to library'), findsOneWidget);
  });

  testWidgets('an edition feed never silently replaces the selected publication', (tester) async {
    await _CatalogPageHarness.mount(tester, (uri) {
      if (uri.path == '/editions') {
        return _feedResponse(
          'Editions',
          publications: [
            {
              'metadata': {'identifier': 'other-edition', 'title': 'Another edition'},
              'links': [
                {'rel': 'download', 'href': '/other.epub', 'type': 'application/epub+zip'},
              ],
            },
          ],
        );
      }
      return _feedResponse(
        'Books',
        publications: [
          {
            'metadata': {'identifier': 'original', 'title': 'Selected book', 'author': 'Writer'},
            'links': [
              {'rel': 'alternate', 'href': '/editions', 'type': 'application/atom+xml;kind=acquisition'},
            ],
          },
        ],
      );
    });
    await tester.tap(find.text('Selected book'));
    await _settleNetwork(tester);
    expect(find.text('Selected book'), findsOneWidget);
    expect(find.text('Another edition'), findsNothing);
    await tester.tap(find.text('Add to library'));
    await _settleNetwork(tester);
    await tester.tap(find.text('Full catalog details'));
    await _settleNetwork(tester);
    expect(find.text('Another edition'), findsOneWidget);
  });

  testWidgets('downloads retry with refreshed catalog settings after a catalog reload', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books', publications: [_book()]));
    final catalog = harness.catalogs.catalogs.single;
    await harness.downloads.start(
      catalog,
      OpdsPublication(id: 'test', title: 'Failed book'),
      OpdsLink(uri: Uri.parse('https://books.test/book.epub'), type: 'application/epub+zip', rels: ['download']),
    );
    expect(harness.importAttempts, 1);
    harness.catalogs.reload();
    await _settleNetwork(tester);
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await _settleNetwork(tester);
    expect(harness.importAttempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download sheet closes without losing jobs and search fits above keyboard', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books'));
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetViewInsets);
    for (var index = 0; index < 3; index++) {
      await harness.downloads.start(
        harness.catalogs.catalogs.single,
        OpdsPublication(id: 'download-$index', title: 'A failed download $index'),
        OpdsLink(uri: Uri.parse('https://books.test/book.epub'), type: 'application/epub+zip', rels: ['download']),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThan(340));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('facet choices and collection View all links navigate to their feeds', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (uri) {
      if (uri.path == '/filtered') return _feedResponse('Filtered books');
      if (uri.path == '/collection') return _feedResponse('Full collection');
      return http.Response(
        jsonEncode({
          'metadata': {'title': 'Browse books'},
          'facets': [
            {
              'metadata': {'title': 'Language'},
              'links': [
                {'title': 'English', 'href': '/filtered?language=en'},
              ],
            },
          ],
          'groups': [
            {
              'metadata': {'title': 'Featured'},
              'publications': [_book()],
              'links': [
                {'rel': 'collection', 'href': '/collection'},
              ],
            },
          ],
        }),
        200,
      );
    });
    expect(find.text('Language:'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'English'));
    await _settleNetwork(tester);
    expect(find.text('Filtered books'), findsOneWidget);
    expect(harness.requests.last, Uri.parse('https://books.test/filtered?language=en'));
    await tester.tap(find.byTooltip('All catalogs'));
    await _settleNetwork(tester);
    await tester.tap(find.text('My catalog'));
    await _settleNetwork(tester);
    await tester.tap(find.text('View all'));
    await _settleNetwork(tester);
    expect(find.text('Full collection'), findsOneWidget);
    expect(harness.requests.last, Uri.parse('https://books.test/collection'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search keeps encoded feed and query through pagination, refresh and route history', (tester) async {
    const query = 'tea & coffee/ž';
    final searchUri = Uri.https('books.test', '/search', {'query': query});
    final pageTwoUri = searchUri.replace(queryParameters: {'query': query, 'page': '2'});
    final harness = await _CatalogPageHarness.mount(tester, (uri) {
      if (uri.path == '/search') {
        final pageTwo = uri.queryParameters['page'] == '2';
        return _feedResponse(
          pageTwo ? 'Search page two' : 'Search results',
          links: [
            {'rel': pageTwo ? 'previous' : 'next', 'href': (pageTwo ? searchUri : pageTwoUri).toString()},
          ],
        );
      }
      return _feedResponse(
        'Catalog home feed',
        links: [
          {'rel': 'search', 'href': 'https://books.test/search{?query}', 'templated': true},
        ],
      );
    });
    final homeRoute = harness.router.routeInformationProvider.value.uri;
    await tester.enterText(find.byType(TextField), query);
    await tester.tap(find.byTooltip('Search catalog'));
    await _settleNetwork(tester);
    expect(find.text('Search results'), findsOneWidget);
    final searchRoute = harness.router.routeInformationProvider.value.uri;
    expect(searchRoute.queryParameters['q'], query);
    final encodedFeed = Uri.parse(searchRoute.queryParameters['feed']!);
    expect(encodedFeed.queryParameters, {'query': query});
    expect(harness.requests.last.queryParameters, {'query': query});
    await tester.tap(find.text('Next'));
    await _settleNetwork(tester);
    expect(find.text('Search page two'), findsOneWidget);
    expect(harness.router.routeInformationProvider.value.uri.queryParameters['q'], query);
    await tester.tap(find.text('Previous'));
    await _settleNetwork(tester);
    expect(find.text('Search results'), findsOneWidget);
    final requestsBeforeRefresh = harness.requests.length;
    await tester.tap(find.byTooltip('Refresh catalog'));
    await _settleNetwork(tester);
    expect(harness.requests.length, requestsBeforeRefresh + 1);
    expect(harness.requests.last.queryParameters, {'query': query});
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, query);

    // The browser delivers history entries through the route information provider.
    await harness.router.routeInformationProvider.didPushRouteInformation(RouteInformation(uri: homeRoute));
    await _settleNetwork(tester);
    expect(find.text('Catalog home feed'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await harness.router.routeInformationProvider.didPushRouteInformation(RouteInformation(uri: searchRoute));
    await _settleNetwork(tester);
    expect(find.text('Search results'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, query);
    expect(harness.requests.last.queryParameters, {'query': query});
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit and remove failures keep the saved catalog and allow retry', (tester) async {
    final harness = await _CatalogPageHarness.mount(
      tester,
      (_) => _feedResponse('Books'),
      initialLocation: '/library/catalogs',
    );
    harness.store.saveFailure = 'Catalog save failed.';
    await tester.tap(find.byTooltip('Catalog options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('opds-name')), 'Renamed catalog');
    await tester.tap(find.text('Save'));
    await _settleNetwork(tester);
    expect(find.text('Catalog save failed.'), findsOneWidget);
    expect(find.byKey(const Key('opds-name')), findsOneWidget);
    expect(harness.catalogs.catalogs.single.name, 'My catalog');
    harness.store.saveFailure = null;
    await tester.tap(find.text('Save'));
    await _settleNetwork(tester);
    expect(find.byKey(const Key('opds-name')), findsNothing);
    expect(find.text('Renamed catalog'), findsOneWidget);

    harness.store.removeFailure = 'Catalog removal failed.';
    await tester.tap(find.byTooltip('Catalog options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await _settleNetwork(tester);
    expect(find.text('Catalog removal failed.'), findsOneWidget);
    expect(find.text('Renamed catalog'), findsOneWidget);
    expect(harness.catalogs.catalogs, hasLength(1));
    harness.store.removeFailure = null;
    await tester.tap(find.byTooltip('Catalog options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await _settleNetwork(tester);
    expect(find.text('No catalogs yet'), findsOneWidget);
    expect(harness.catalogs.catalogs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed feed can retry to empty results and refresh to books', (tester) async {
    var attempt = 0;
    final harness = await _CatalogPageHarness.mount(tester, (_) {
      attempt++;
      if (attempt == 1) return http.Response('Unavailable', 503);
      return _feedResponse('Books', publications: attempt == 2 ? [] : [_book()]);
    });
    expect(
      find.textContaining('HTTP 503'),
      findsOneWidget,
      reason:
          'requests=${harness.requests}; texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
    );
    await tester.tap(find.text('Retry'));
    await _settleNetwork(tester);
    expect(find.textContaining('HTTP 503'), findsNothing);
    expect(find.text('No books or sections found.'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh catalog'));
    await _settleNetwork(tester);
    expect(find.text('A book'), findsOneWidget);
    expect(find.text('No books or sections found.'), findsNothing);
    expect(harness.requests, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open publication details cannot download after catalog or account changes', (tester) async {
    final harness = await _CatalogPageHarness.mount(tester, (_) => _feedResponse('Books', publications: [_book()]));
    for (final changeAccount in [false, true]) {
      await tester.tap(find.text('A book'));
      await _settleNetwork(tester);
      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(find.text('Download EPUB'), findsOneWidget);
      if (changeAccount) {
        harness.catalogs.setScope('local--other');
      } else {
        await harness.catalogs.save(
          OpdsCatalog(id: 'one', name: 'Changed catalog', uri: Uri.parse('https://other-books.test/feed')),
        );
      }
      await _settleNetwork(tester);
      await tester.tap(find.text('Download EPUB'));
      await _settleNetwork(tester);
      expect(find.text('The catalog or account changed. Close these details and reopen the book.'), findsOneWidget);
      expect(harness.downloads.jobs, isEmpty);
      expect(harness.importAttempts, 0);
      expect(harness.requests.where((uri) => uri.path.endsWith('.epub')), isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to catalog'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an editor opened in another account cannot save into the active account', (tester) async {
    final harness = await _CatalogPageHarness.mount(
      tester,
      (_) => _feedResponse('Books'),
      initialLocation: '/library/catalogs',
    );
    await tester.tap(find.byTooltip('Catalog options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('opds-name')), 'Wrong account catalog');
    harness.catalogs.setScope('local--other');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settleNetwork(tester);
    expect(find.text('The active account changed. Close this editor and try again.'), findsOneWidget);
    expect(find.byKey(const Key('opds-name')), findsOneWidget);
    expect(harness.catalogs.catalogs, isEmpty);
    expect(harness.store.load('local--other'), isEmpty);
    expect(harness.store.load('local--guest').single.name, 'My catalog');
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('add and browse a catalog at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
        ..setScope('local--guest');
      final downloads = OpdsDownloads(captureImport: () => throw StateError('unused'));
      final gateway = OpdsHttpClient(
        clientFactory: () => MockRelayClient(
          (_) async => http.Response(
            '{"metadata":{"title":"Fixture books"},"publications":[{"metadata":{"title":"A book","author":"An author"},"links":[{"rel":"http://opds-spec.org/acquisition/open-access","href":"book.epub","type":"application/epub+zip"}]}]}',
            200,
          ),
        ),
      );
      final router = GoRouter(
        initialLocation: '/library/catalogs',
        routes: [
          GoRoute(
            path: '/library/catalogs',
            builder: (_, _) => CatalogsPage(httpClient: gateway),
            routes: [
              GoRoute(
                path: ':catalogId',
                builder: (_, state) => CatalogsPage(catalogId: state.pathParameters['catalogId'], httpClient: gateway),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: catalogs),
            ChangeNotifierProvider.value(value: downloads),
          ],
          child: MaterialApp.router(
            theme: AppTheme.eink,
            routerConfig: router,
            builder: (_, child) => AppMotionScope(reduceAnimations: true, child: Scaffold(body: child!)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No catalogs yet'), findsOneWidget);
      await tester.tap(find.text('Add catalog').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('opds-name')), 'My catalog');
      await tester.enterText(find.byKey(const Key('opds-url')), 'https://books.test/feed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('My catalog'), findsOneWidget);
      await tester.tap(find.text('My catalog'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.text('A book'),
        findsOneWidget,
        reason:
            '${tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).join(' | ')}; progress=${find.byType(CircularProgressIndicator).evaluate().length}',
      );
      expect(find.text('An author'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      catalogs.dispose();
      downloads.dispose();
    });
  }
}
