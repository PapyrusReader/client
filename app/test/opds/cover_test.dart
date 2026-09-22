import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book/cover_loading_placeholder.dart';
import 'package:papyrus/widgets/opds/opds_publication_tile.dart';

final _catalog = OpdsCatalog(id: 'catalog', name: 'Catalog', uri: Uri.parse('https://books.test/feed'));
final _coverUri = Uri.parse('https://books.test/cover.png');

class _PendingCoverClient extends OpdsHttpClient {
  _PendingCoverClient({super.cache});
  final response = Completer<OpdsResponse>();
  var requests = 0;

  @override
  Future<OpdsResponse> get(
    OpdsCatalog catalog,
    Uri uri, {
    OpdsCredentials? credentials,
    OpdsCancellation? cancellation,
    void Function(int, int?)? onProgress,
    int maxBytes = 8 * 1024 * 1024,
  }) {
    requests++;
    return response.future;
  }
}

Future<void> _mount(
  WidgetTester tester,
  OpdsHttpClient client, {
  required ThemeData theme,
  required Size size,
  Uri? uri,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Center(
      child: OpdsCover(catalog: _catalog, uri: uri, httpClient: client, width: size.width, height: size.height),
    ),
  ),
);

void main() {
  testWidgets('persisted artwork appears without a new request or loading placeholder', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs)..setScope('guest');
    await cache.write(
      cache.capture(_catalog, _coverUri)!,
      OpdsResponse(
        uri: _coverUri,
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        headers: {'content-type': 'image/png'},
      ),
    );
    final client = _PendingCoverClient(cache: OpdsResourceCache(prefs)..setScope('guest'));
    await _mount(tester, client, theme: AppTheme.eink, size: const Size(180, 270), uri: _coverUri);
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(() => precacheImage(image.image, tester.element(find.byType(OpdsCover))));
    await tester.pumpAndSettle();
    expect(find.byType(CoverLoadingPlaceholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(client.requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid optional artwork falls back when caching is enabled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('guest');
    final client = _PendingCoverClient(cache: cache);
    await _mount(
      tester,
      client,
      theme: AppTheme.eink,
      size: const Size(180, 270),
      uri: Uri.parse('https://user:secret@books.test/cover.png'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CoverLoadingPlaceholder), findsNothing);
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(client.requests, 0);
    expect(tester.takeException(), isNull);
  });
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark), ('eink', AppTheme.eink)]) {
    for (final size in [const Size(60, 90), const Size(180, 270)]) {
      testWidgets('$name $size shares library loading state until request fails', (tester) async {
        final client = _PendingCoverClient();
        await _mount(tester, client, theme: theme, size: size, uri: _coverUri);

        expect(find.byType(CoverLoadingPlaceholder), findsOneWidget);
        expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
        expect(find.text('Loading…'), size.width < 72 ? findsNothing : findsOneWidget);
        expect(tester.getSize(find.byType(OpdsCover)), size);

        client.response.completeError(const OpdsException('Artwork unavailable'));
        await tester.pumpAndSettle();
        expect(find.byType(CoverLoadingPlaceholder), findsNothing);
        expect(find.byIcon(Icons.menu_book), findsOneWidget);
        expect(tester.getSize(find.byType(OpdsCover)), size);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('missing cover skips loading and does not request artwork', (tester) async {
    final client = _PendingCoverClient();
    await _mount(tester, client, theme: AppTheme.light, size: const Size(180, 270));
    expect(find.byType(CoverLoadingPlaceholder), findsNothing);
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(client.requests, 0);
  });

  testWidgets('downloaded artwork replaces loading after image decoding', (tester) async {
    final client = _PendingCoverClient();
    await _mount(tester, client, theme: AppTheme.dark, size: const Size(180, 270), uri: _coverUri);
    expect(find.byType(CoverLoadingPlaceholder), findsOneWidget);

    client.response.complete(
      OpdsResponse(
        uri: _coverUri,
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        headers: {'content-type': 'image/png'},
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(() => precacheImage(image.image, tester.element(find.byType(OpdsCover))));
    await tester.pumpAndSettle();
    expect(find.byType(CoverLoadingPlaceholder), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
