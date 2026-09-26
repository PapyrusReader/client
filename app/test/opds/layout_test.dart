@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_library.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:papyrus/widgets/opds/opds_publication_details.dart';
import 'package:papyrus/widgets/book_details/book_details_tab_rail.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/pages/catalog_book_page.dart';
import 'package:papyrus/pages/catalogs_page.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/services/book_import_result.dart';
import 'package:papyrus/services/book_import_session.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book_details/book_header.dart';
import 'package:papyrus/widgets/library/book_grid.dart';
import 'package:papyrus/widgets/opds/catalog_source_tile.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_store_test.dart' show MemorySecrets;
import 'relay_fixture_client.dart';

const _capture = bool.fromEnvironment('CAPTURE_OPDS');
const _fontDirectory = String.fromEnvironment('FLUTTER_FONT_DIR');
final _boundary = GlobalKey();

ThemeData _captureTheme(ThemeData theme) {
  if (_fontDirectory.isEmpty) return theme;
  // Explicit component styles omit a font family in the app. Flutter's test
  // fallback is Ahem rather than the platform font, so resolve it for captures.
  ButtonStyle? font(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => style.textStyle?.resolve(states)?.copyWith(fontFamily: 'Roboto'),
    ),
  );
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
    textButtonTheme: TextButtonThemeData(style: font(theme.textButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: font(theme.outlinedButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: font(theme.elevatedButtonTheme.style)),
    chipTheme: theme.chipTheme.copyWith(labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto')),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var hop = 0; hop < 3; hop++) {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  await _settle(tester);
  if (!_capture) return;
  // Image codecs run outside the widget-test fake clock.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/catalog-review')..createSync(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_fontDirectory.isNotEmpty) {
      for (final (family, file) in [('Roboto', 'Roboto-Regular.ttf'), ('MaterialIcons', 'MaterialIcons-Regular.otf')]) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(File('$_fontDirectory/$file').readAsBytesSync())))).load();
      }
      await (FontLoader('MadimiOne')..addFont(rootBundle.load('fonts/MadimiOne-Regular.ttf'))).load();
    }
  });

  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark), ('eink', AppTheme.eink)]) {
    for (final (width, scale) in [
      (360.0, 1.0),
      (424.0, 1.0),
      (600.0, 1.0),
      (840.0, 1.0),
      (1280.0, 1.0),
      (2507.0, 1.0),
      (360.0, 2.0),
    ]) {
      testWidgets('$name $width text $scale catalog journey in the app shell', (tester) async {
        tester.view.physicalSize = Size(
          width,
          width > 2000
              ? 1322
              : width == 424
              ? 951
              : 900,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        SharedPreferences.setMockInitialValues({});
        final store = OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets());
        await store.save(
          'local--guest',
          OpdsCatalog(id: 'gutenberg', name: 'Project Gutenberg', uri: Uri.parse('https://www.gutenberg.org/feed')),
        );
        await store.save(
          'local--guest',
          OpdsCatalog(id: 'standard', name: 'Standard Ebooks', uri: Uri.parse('https://standard.test/opds')),
        );
        final dataStore = DataStore();
        final opdsLibrary = OpdsLibrary(await SharedPreferences.getInstance(), dataStore: dataStore);
        final cache = OpdsResourceCache(await SharedPreferences.getInstance());
        final catalogs = OpdsCatalogs(store, library: opdsLibrary, cache: cache)..setScope('local--guest');
        final cover = File('assets/images/book_placeholder.jpg').readAsBytesSync();
        var offline = false;
        final gateway = OpdsHttpClient(
          cache: cache,
          clientFactory: () => MockRelayClient((request) async {
            if (offline) throw http.ClientException('Offline');
            if (request.url.path.endsWith('.jpg')) {
              return http.Response.bytes(cover, 200, headers: {'content-type': 'image/jpeg'});
            }
            if (request.url.path.endsWith('.epub')) {
              return http.Response('Review book bytes', 200, headers: {'content-type': 'application/epub+zip'});
            }
            return http.Response(
              jsonEncode({
                'metadata': {
                  'title': request.url.path == '/editions' ? 'Pride and Prejudice by Jane Austen' : 'Popular books',
                },
                'links': [
                  {'rel': 'previous', 'href': '/feed?page=1'},
                  {'rel': 'next', 'href': '/feed?page=3'},
                ],
                'navigation': [
                  if (request.url.path != '/editions')
                    {
                      'title': 'Browse by author',
                      'href': '/authors',
                      'description': 'Explore writers and their collections',
                    },
                ],
                'publications': [
                  for (final (id, title, author)
                      in request.url.path == '/editions'
                          ? [
                              ('pride', 'Pride and Prejudice', 'Jane Austen'),
                              ('pride-images', 'Pride and Prejudice', 'Jane Austen'),
                            ]
                          : [
                              ('pride', 'Pride and Prejudice', 'Jane Austen'),
                              ('moby', 'Moby Dick; or, The Whale', 'Herman Melville'),
                              (
                                'frankenstein',
                                'Frankenstein; or, The Modern Prometheus',
                                'Mary Wollstonecraft Shelley',
                              ),
                              ('alice', 'Alice’s Adventures in Wonderland', 'Lewis Carroll'),
                            ])
                    {
                      'metadata': {
                        'identifier': id,
                        'title': title,
                        'author': author,
                        'language': 'English',
                        'publisher': 'Project Gutenberg',
                        'subject': ['Fiction', 'Courtship', 'England — Social life and customs'],
                        'description':
                            'Title: $title\n\nSummary: A classic novel, available to add to your Papyrus library.\n\n'
                            'This edition preserves the original text and includes illustrations and notes.\n\n'
                            'Language: English\n\nPublished: 1813\n\nRights: Public domain in the USA.\n\n'
                            'Credits: Prepared by volunteers.\n\nNote: Additional catalog information is preserved here.',
                      },
                      if (id != 'frankenstein')
                        'images': [
                          {'href': '/cover.jpg', 'type': 'image/jpeg'},
                        ],
                      'links': [
                        {
                          'rel': 'download',
                          'href': '/$id.epub',
                          'type': 'application/epub+zip',
                          'title': request.url.path == '/editions'
                              ? id == 'pride'
                                    ? 'EPUB (no images, older E-readers)'
                                    : 'EPUB3 (E-readers incl. Send-to-Kindle)'
                              : 'EPUB with illustrations',
                        },
                        {
                          'rel': 'download',
                          'href': '/$id-text.epub',
                          'type': 'application/epub+zip',
                          'title': 'EPUB, text only',
                        },
                        {'rel': 'download', 'href': '/$id.daisy', 'type': 'application/x-dtbook+xml', 'title': 'DAISY'},
                      ],
                    },
                ],
              }),
              200,
              headers: {'content-type': 'application/opds+json; charset=utf-8'},
            );
          }),
        );
        final downloads = OpdsDownloads(
          library: opdsLibrary,
          httpClient: gateway,
          captureImport: () => BookImportSession(
            process: (_, _) async => const BookImportResult(
              bookId: 'review-book',
              title: 'Pride and Prejudice',
              author: 'Jane Austen',
              fileSize: 17,
              fileHash: 'review',
              fileExtension: 'epub',
            ),
            deleteFile: (_) async {},
            isCurrent: () => true,
            commit: (_, _) async {
              final book = Book(
                id: 'review-book',
                title: 'Pride and Prejudice',
                author: 'Jane Austen',
                addedAt: DateTime(2026),
              );
              dataStore.replaceBooksFromSync([book]);
              return book;
            },
          ),
        );
        final sidebar = SidebarProvider();
        final library = LibraryProvider();
        final reference = Book(
          id: 'reference',
          title: 'Pride and Prejudice',
          author: 'Jane Austen',
          addedAt: DateTime(2026),
        );
        final router = GoRouter(
          initialLocation: '/library/catalogs',
          routes: [
            ShellRoute(
              builder: (_, _, child) => AdaptiveAppShell(child: child),
              routes: [
                GoRoute(
                  path: '/library/catalogs',
                  builder: (_, _) => const CatalogsPage(),
                  routes: [
                    GoRoute(
                      path: ':catalogId',
                      builder: (_, state) => CatalogsPage(
                        catalogId: state.pathParameters['catalogId'],
                        feedUri: Uri.tryParse(state.uri.queryParameters['feed'] ?? '')?.hasScheme == true
                            ? Uri.parse(state.uri.queryParameters['feed']!)
                            : null,
                      ),
                      routes: [catalogBookRoute()],
                    ),
                  ],
                ),
                GoRoute(
                  path: '/reference',
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        BookHeader(book: reference, isDesktop: width >= 1280),
                        const SizedBox(height: 24),
                        Expanded(
                          child: BookGrid(books: [reference], libraryViewMode: LibraryViewMode.grid),
                        ),
                      ],
                    ),
                  ),
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
              ChangeNotifierProvider.value(value: dataStore),
              ChangeNotifierProvider.value(value: sidebar),
              ChangeNotifierProvider.value(value: library),
              Provider.value(value: gateway),
            ],
            child: RepaintBoundary(
              key: _boundary,
              child: MaterialApp.router(
                theme: _captureTheme(theme),
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: AppMotionScope(reduceAnimations: true, child: child!),
                ),
              ),
            ),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          catalogs.dispose();
          downloads.dispose();
          opdsLibrary.dispose();
          cache.dispose();
          dataStore.dispose();
          sidebar.dispose();
          library.dispose();
        });
        final label = '$name-${width.toInt()}-${scale.toInt()}x';
        await _snapshot(tester, '$label-sources');
        if (width < 840) {
          expect(tester.getSize(find.byKey(const Key('catalog-mobile-header'))).height, kToolbarHeight);
          expect(find.byKey(const Key('catalog-header-divider')), findsNothing);
          expect(find.byTooltip('Catalog options'), findsNothing);
          for (final (direction, action) in [(1.0, 'edit'), (-1.0, 'delete')]) {
            final sourceRect = tester.getRect(find.byType(CatalogSourceTile).first);
            final gesture = await tester.startGesture(sourceRect.center);
            await gesture.moveBy(Offset(direction * 20, 0));
            await tester.pump();
            await gesture.moveBy(Offset(direction * sourceRect.width * 0.6, 0));
            await _snapshot(tester, '$label-source-$action-swipe');
            expect(find.byType(BottomSheet), findsNothing);
            await gesture.up();
            await _settle(tester);
            expect(find.byType(BottomSheet), findsOneWidget);
            if (action == 'edit') {
              expect(find.byKey(const Key('opds-name')), findsOneWidget);
            } else {
              expect(find.text('Remove catalog'), findsOneWidget);
            }
            await tester.tap(find.text('Cancel'));
            await _settle(tester);
          }
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(
            tester.getBottomRight(find.byType(FloatingActionButton)).dy,
            lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
          );
          expect(
            tester.getTopLeft(find.byTooltip('Downloads')).dy,
            lessThan(tester.getBottomLeft(find.text('Catalogs').last).dy),
          );
        } else {
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(find.widgetWithText(FilledButton, 'Add catalog'), findsOneWidget);
        }
        await tester.tap(find.text('Project Gutenberg'));
        await _snapshot(tester, '$label-feed');
        offline = true;
        await tester.tap(find.byTooltip('Refresh catalog'));
        await _snapshot(tester, '$label-cached-feed');
        expect(find.text('Showing saved content. Could not refresh this catalog.'), findsOneWidget);
        offline = false;
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          find.text('Popular books'),
          findsOneWidget,
          reason: tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | '),
        );
        await tester.scrollUntilVisible(
          find.text('Next'),
          200,
          scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
        );
        await _snapshot(tester, '$label-pagination');
        tester
            .state<ScrollableState>(
              find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
            )
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        router.go(
          Uri(path: '/library/catalogs/gutenberg', queryParameters: {'feed': 'https://books.test/editions'}).toString(),
        );
        await _snapshot(tester, '$label-editions');
        expect(find.text('Pride and Prejudice'), findsNWidgets(2));
        router.go('/library/catalogs/gutenberg');
        await _settle(tester);
        await tester.scrollUntilVisible(
          find.text('Pride and Prejudice'),
          200,
          scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pride and Prejudice'));
        await _snapshot(tester, '$label-details');
        if (width < 840) {
          final header = find.byKey(const Key('catalog-book-mobile-header'));
          expect(tester.getSize(header).height, kToolbarHeight);
          expect(find.byKey(const Key('catalog-book-header-divider')), findsNothing);
          final rail = find.byType(BookDetailsTabRail);
          await tester.dragFrom(Offset(width / 2, 700), const Offset(0, -1600));
          await tester.pumpAndSettle();
          expect(tester.getRect(rail).left, 0);
          expect(tester.getRect(rail).width, width);
          expect(tester.getTopLeft(rail).dy, tester.getBottomLeft(header).dy);
          await _snapshot(tester, '$label-details-scrolled');
        }
        expect(find.text('Details'), findsOneWidget);
        await tester.ensureVisible(find.text('Description'));
        await _snapshot(tester, '$label-details-content');
        if (find.byType(NestedScrollView).evaluate().isNotEmpty) {
          await tester.dragFrom(Offset(width / 2, 200), const Offset(0, 2500));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Add to library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to library'));
        await _snapshot(tester, '$label-formats');
        await tester.ensureVisible(find.textContaining('Other catalog options'));
        await tester.tap(find.textContaining('Other catalog options'));
        await _snapshot(tester, '$label-formats-expanded');
        if (_capture && width >= 840) {
          final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(find.textContaining('Other catalog options')));
          await _snapshot(tester, '$label-formats-hover');
          await mouse.removePointer();
        }
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final selected = tester.widget<OpdsPublicationDetails>(find.byType(OpdsPublicationDetails)).publication;
        await tester.tap(find.byTooltip('Downloads'));
        await _snapshot(tester, '$label-downloads');
        final reviewLink = selected.links.firstWhere(OpdsDownloads.supports);
        final transfer = downloads.start(catalogs.catalogs.first, selected, reviewLink);
        await _settle(tester);
        await transfer;
        await _snapshot(tester, '$label-downloads-complete');
        expect(find.text('Added to library'), findsOneWidget);
        expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Open book')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await _snapshot(tester, '$label-owned-details');
        expect(find.text('In library'), findsNothing);
        expect(find.text('Open book'), findsOneWidget);
        await tester.tap(find.text('Download options'));
        await _snapshot(tester, '$label-owned-formats');
        await tester.tap(find.text('Close'));
        router.go('/library/catalogs');
        await _settle(tester);
        await tester.tap(
          find.byType(FloatingActionButton).evaluate().isNotEmpty
              ? find.byTooltip('Add catalog')
              : find.text('Add catalog'),
        );
        await _snapshot(tester, '$label-editor');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _snapshot(tester, '$label-editor-keyboard');
        tester.view.resetViewInsets();
        await tester.tap(find.text('Cancel'));
        await _settle(tester);
        if (_capture && width >= 1280 && scale == 1) {
          router.go('/reference');
          await _snapshot(tester, '$label-library-reference');
        }
      });
    }
  }
}
