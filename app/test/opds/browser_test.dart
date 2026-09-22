import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'relay_fixture_client.dart';

void main() {
  final catalog = OpdsCatalog(id: 'c', name: 'Books', uri: Uri.parse('https://books.test/feed'));
  Future<OpdsResourceCache> warmCache() async {
    SharedPreferences.setMockInitialValues({});
    final cache = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('alice');
    await cache.write(
      cache.capture(catalog, catalog.uri)!,
      OpdsResponse(
        uri: Uri.parse('https://cdn.test/redirect/feed'),
        bytes: Uint8List.fromList(
          utf8.encode('{"metadata":{"title":"Cached"},"navigation":[{"title":"Next","href":"next"}]}'),
        ),
        headers: {'content-type': 'application/opds+json'},
      ),
    );
    return cache;
  }

  test('shows cached feed immediately with redirect base while refreshing', () async {
    final cache = await warmCache();
    final response = Completer<http.Response>();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(cache: cache, clientFactory: () => MockRelayClient((_) => response.future)),
    );
    final load = browser.load(catalog, catalog.uri);
    expect(browser.feed?.title, 'Cached');
    expect(browser.feed?.navigation.single.uri.toString(), 'https://cdn.test/redirect/next');
    expect(browser.loading, isTrue);
    expect(browser.isCached, isTrue);
    expect(browser.fetchedAt, isNotNull);
    response.complete(http.Response('{"metadata":{"title":"Fresh"},"navigation":[]}', 200));
    await load;
    expect(browser.feed?.title, 'Fresh');
    expect(browser.isCached, isFalse);
    expect(browser.loading, isFalse);
    expect(cache.read(cache.capture(catalog, catalog.uri)!)!.response.text, contains('Fresh'));
    browser.dispose();
  });

  for (final status in [500, 401, 403]) {
    test('revalidation HTTP $status ${status == 500 ? 'retains' : 'invalidates'} protected cached feed', () async {
      final cache = await warmCache();
      final browser = OpdsBrowser(
        httpClient: OpdsHttpClient(
          cache: cache,
          clientFactory: () => MockRelayClient((_) async => http.Response('failure', status)),
        ),
      );
      await browser.load(catalog, catalog.uri);
      expect(browser.error, isNotNull);
      expect(browser.feed?.title, status == 500 ? 'Cached' : null);
      expect(cache.read(cache.capture(catalog, catalog.uri)!), status == 500 ? isNotNull : isNull);
      browser.dispose();
    });
  }

  test('scope A to B to A rejects a late feed and cache write', () async {
    final cache = await warmCache();
    final response = Completer<http.Response>();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(cache: cache, clientFactory: () => MockRelayClient((_) => response.future)),
    );
    final load = browser.load(catalog, catalog.uri);
    await Future<void>.delayed(Duration.zero);
    cache.setScope('bob');
    cache.setScope('alice');
    response.complete(http.Response('{"metadata":{"title":"Obsolete"},"navigation":[]}', 200));
    await load;
    expect(browser.feed, isNull);
    expect(cache.read(cache.capture(catalog, catalog.uri)!)!.response.text, contains('Cached'));
    browser.dispose();
  });

  test('one browser authorization failure immediately clears another idle feed', () async {
    final cache = await warmCache();
    final client = OpdsHttpClient(
      cache: cache,
      clientFactory: () => MockRelayClient(
        (request) async => request.url.path == '/details'
            ? http.Response('denied', 401)
            : http.Response('{"metadata":{"title":"Private"},"navigation":[]}', 200),
      ),
    );
    final parent = OpdsBrowser(httpClient: client);
    final details = OpdsBrowser(httpClient: client);
    await parent.load(catalog, catalog.uri);
    expect(parent.feed?.title, 'Private');
    var notifications = 0;
    parent.addListener(() => notifications++);
    await details.load(catalog, catalog.uri.resolve('details'));
    expect(parent.feed, isNull);
    expect(parent.error, contains('Refresh'));
    expect(parent.loading, isFalse);
    expect(parent.cacheInvalidated, isTrue);
    expect(notifications, 1);
    expect(details.authorizationFailed, isTrue);
    expect(details.error, contains('credentials'));
    await parent.load(catalog, catalog.uri);
    expect(parent.feed?.title, 'Private');
    expect(parent.cacheInvalidated, isFalse);
    parent.dispose();
    details.dispose();
  });

  test('scope switch clears an idle feed immediately and unsubscribes on disposal', () async {
    final cache = await warmCache();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        cache: cache,
        clientFactory: () =>
            MockRelayClient((_) async => http.Response('{"metadata":{"title":"Private"},"navigation":[]}', 200)),
      ),
    );
    await browser.load(catalog, catalog.uri);
    var notifications = 0;
    browser.addListener(() => notifications++);
    cache.setScope('bob');
    expect(browser.feed, isNull);
    expect(browser.error, contains('Refresh'));
    expect(browser.loading, isFalse);
    expect(browser.cacheInvalidated, isTrue);
    expect(notifications, 1);
    browser.dispose();
    cache.setScope('alice');
    expect(notifications, 1);
  });

  test('simultaneous authorization failures mark both browser contexts invalid', () async {
    final cache = await warmCache();
    final parentResponse = Completer<http.Response>();
    final detailResponse = Completer<http.Response>();
    final client = OpdsHttpClient(
      cache: cache,
      clientFactory: () =>
          MockRelayClient((request) => request.url.path == '/details' ? detailResponse.future : parentResponse.future),
    );
    final parent = OpdsBrowser(httpClient: client);
    final details = OpdsBrowser(httpClient: client);
    final parentLoad = parent.load(catalog, catalog.uri);
    final detailLoad = details.load(catalog, catalog.uri.resolve('details'));
    await Future<void>.delayed(Duration.zero);
    parentResponse.complete(http.Response('denied', 401));
    await parentLoad;
    expect(parent.authorizationFailed, isTrue);
    expect(details.cacheInvalidated, isTrue);
    detailResponse.complete(http.Response('denied', 401));
    await detailLoad;
    expect(parent.feed, isNull);
    expect(details.feed, isNull);
    expect(details.loading, isFalse);
    expect(details.error, isNotNull);
    parent.dispose();
    details.dispose();
  });

  test('invalidating another catalog retains the loaded feed', () async {
    final cache = await warmCache();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        cache: cache,
        clientFactory: () =>
            MockRelayClient((_) async => http.Response('{"metadata":{"title":"Private"},"navigation":[]}', 200)),
      ),
    );
    await browser.load(catalog, catalog.uri);
    await cache.invalidateCatalog(OpdsCatalog(id: 'another', name: 'Other', uri: catalog.uri));
    expect(browser.feed?.title, 'Private');
    expect(browser.cacheInvalidated, isFalse);
    browser.dispose();
  });

  test('unsupported responses never replace the cached parsed feed', () async {
    final cache = await warmCache();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        cache: cache,
        clientFactory: () => MockRelayClient((_) async => http.Response('<html>Login</html>', 200)),
      ),
    );
    await browser.load(catalog, catalog.uri);
    expect(browser.feed?.title, 'Cached');
    expect(browser.error, isNotNull);
    expect(cache.read(cache.capture(catalog, catalog.uri)!)!.response.text, contains('Cached'));
    final other = catalog.uri.resolve('uncached');
    await browser.load(catalog, other);
    expect(browser.feed, isNull);
    expect(cache.read(cache.capture(catalog, other)!), isNull);
    browser.dispose();
  });

  test('root search and OpenSearch remain usable offline with redirected bases', () async {
    final cache = await warmCache();
    Future<void> store(Uri requested, Uri finalUri, String body) => cache.write(
      cache.capture(catalog, requested)!,
      OpdsResponse(uri: finalUri, bytes: Uint8List.fromList(utf8.encode(body)), headers: {}),
    );
    await store(
      catalog.uri,
      Uri.parse('https://cdn.test/base/feed'),
      '{"metadata":{"title":"Root"},"links":[{"rel":"search","href":"search.xml","type":"application/opensearchdescription+xml"}],"navigation":[]}',
    );
    await store(
      Uri.parse('https://cdn.test/base/search.xml'),
      Uri.parse('https://search.test/redirect/description.xml'),
      '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/"><Url type="application/atom+xml" template="results?q={searchTerms}"/></OpenSearchDescription>',
    );
    var requests = 0;
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        cache: cache,
        clientFactory: () => MockRelayClient((_) async {
          requests++;
          throw StateError('offline');
        }),
      ),
    );
    await browser.load(catalog, catalog.uri.resolve('section'));
    expect((await browser.search('some books')).toString(), 'https://search.test/redirect/results?q=some%20books');
    expect(requests, 1);
    browser.dispose();
  });

  test('authorization failure resolving search clears the previous feed', () async {
    final cache = await warmCache();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        cache: cache,
        clientFactory: () => MockRelayClient(
          (request) async => request.url.path == '/section'
              ? http.Response('{"metadata":{"title":"Private"},"navigation":[]}', 200)
              : http.Response('denied', 403),
        ),
      ),
    );
    // Remove the cached root so resolving search must ask the server.
    await cache.remove(cache.capture(catalog, catalog.uri)!);
    await browser.load(catalog, catalog.uri.resolve('section'));
    expect(browser.feed?.title, 'Private');
    await expectLater(browser.search('books'), throwsA(isA<OpdsAuthorizationException>()));
    expect(browser.feed, isNull);
    expect(browser.authorizationFailed, isTrue);
    browser.dispose();
  });
  test('late feed results cannot replace the current navigation', () async {
    final oldResponse = Completer<http.Response>();
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        clientFactory: () => MockRelayClient((request) async {
          if (request.url.path == '/old') return oldResponse.future;
          return http.Response('{"metadata":{"title":"New"},"navigation":[]}', 200);
        }),
      ),
    );
    final old = browser.load(catalog, Uri.parse('https://books.test/old'));
    await Future<void>.delayed(Duration.zero);
    await browser.load(catalog, Uri.parse('https://books.test/new'));
    oldResponse.complete(http.Response('{"metadata":{"title":"Old"},"navigation":[]}', 200));
    await old;
    expect(browser.feed?.title, 'New');
    browser.dispose();
  });

  test('resolves root search while browsing a subsection', () async {
    final browser = OpdsBrowser(
      httpClient: OpdsHttpClient(
        clientFactory: () => MockRelayClient((request) async {
          return http.Response(
            request.url.path == '/feed'
                ? '{"metadata":{"title":"Root"},"links":[{"rel":"search","href":"search{?query}","templated":true,"type":"application/opds+json"}],"navigation":[]}'
                : '{"metadata":{"title":"Section"},"navigation":[]}',
            200,
          );
        }),
      ),
    );
    await browser.load(catalog, Uri.parse('https://books.test/section'));
    final uri = await browser.search('a & b');
    expect(uri.queryParameters['query'], 'a & b');
    browser.dispose();
  });
}
