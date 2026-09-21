import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';

void main() {
  final catalog = OpdsCatalog(id: 'one', name: 'Books', uri: Uri.parse('https://books.test/opds'));
  const credentials = OpdsCredentials(username: 'reader', password: 'secret');

  test('queues cover fanout and cancels waiting requests before they reach the server', () async {
    final pending = <Completer<http.Response>>[];
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient((_) {
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      }),
    );
    final running = List.generate(4, (_) => gateway.get(catalog, catalog.uri));
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(4));
    final cancellation = OpdsCancellation();
    final queued = gateway.get(catalog, catalog.uri, cancellation: cancellation);
    final cancelled = expectLater(queued, throwsA(isA<OpdsCancelled>()));
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(4));
    cancellation.cancel();
    await cancelled;
    for (final response in pending) {
      response.complete(http.Response('book', 200, headers: {'x-opds-url': catalog.uri.toString()}));
    }
    await Future.wait(running);
    expect(pending, hasLength(4));
  });

  test('retries temporary relay capacity errors without a direct request', () async {
    var attempts = 0;
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient((request) async {
        expect(request.method, 'POST');
        if (++attempts == 1) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'OPDS_RELAY_ERROR',
                'message': 'The catalog relay is busy.',
                'details': {'retryable': true},
              },
            }),
            503,
          );
        }
        return http.Response('book', 200, headers: {'x-opds-url': catalog.uri.toString()});
      }),
    );
    expect((await gateway.get(catalog, catalog.uri)).text, 'book');
    expect(attempts, 2);
  });

  test('fetches through the backend without account authentication or a direct catalog request', () async {
    final seen = <http.Request>[];
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient((request) async {
        seen.add(request);
        return http.Response('book', 200, headers: {'x-opds-url': 'https://cdn.test/book.epub'});
      }),
    );
    final response = await gateway.get(catalog, catalog.uri, credentials: credentials);
    expect(seen, hasLength(1));
    expect(seen.single.url, PapyrusApiConfig.fromEnvironment().endpoint('/opds/relay'));
    expect(seen.single.method, 'POST');
    expect(seen.single.headers.containsKey('authorization'), isFalse);
    expect(jsonDecode(seen.single.body), {
      'url': catalog.uri.toString(),
      'catalog_url': catalog.uri.toString(),
      'max_bytes': 8 * 1024 * 1024,
      'credentials': {'username': 'reader', 'password': 'secret'},
    });
    expect(response.uri, Uri.parse('https://cdn.test/book.epub'));
    expect(utf8.decode(response.bytes), 'book');
  });

  test('reports relay errors without returning upstream pages or credentials', () async {
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'OPDS_RELAY_ERROR', 'message': 'Check the catalog credentials.'},
          }),
          401,
        ),
      ),
    );
    await expectLater(
      gateway.get(catalog, catalog.uri, credentials: credentials),
      throwsA(isA<OpdsException>().having((e) => e.message, 'message', 'Check the catalog credentials.')),
    );
  });

  test('network failure reports the server and never falls back to a direct request', () async {
    var attempts = 0;
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient((_) async {
        attempts++;
        throw http.ClientException('Failed to fetch');
      }),
    );
    await expectLater(
      gateway.get(catalog, catalog.uri),
      throwsA(isA<OpdsConnectionException>().having((e) => e.message, 'message', contains('server'))),
    );
    expect(attempts, 1);
  });

  test('rejects successful responses without upstream URL metadata', () async {
    final gateway = OpdsHttpClient(clientFactory: () => MockClient((_) async => http.Response('book', 200)));
    await expectLater(gateway.get(catalog, catalog.uri), throwsA(isA<OpdsException>()));
  });
}
