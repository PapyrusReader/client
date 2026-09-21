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

  test('uses the currently selected server for subsequent requests', () async {
    final seen = <http.Request>[];
    var server = 'https://papyrus.test';
    final gateway = OpdsHttpClient(
      apiConfig: () => PapyrusApiConfig(serverBaseUri: Uri.parse(server)),
      clientFactory: () => MockClient((request) async {
        seen.add(request);
        return http.Response('book', 200, headers: {'x-opds-url': 'https://cdn.test/book.epub'});
      }),
    );
    final response = await gateway.get(catalog, catalog.uri, credentials: credentials);
    server = 'https://custom.test';
    await gateway.get(catalog, catalog.uri);
    expect(seen.first.url.host, 'papyrus.test');
    expect(seen.last.url.host, 'custom.test');
    expect(seen.first.headers.containsKey('authorization'), isFalse);
    expect(seen.last.headers.containsKey('authorization'), isFalse);
    expect(response.uri, Uri.parse('https://cdn.test/book.epub'));
    expect(utf8.decode(response.bytes), 'book');
  });

  test('reports authentication errors without exposing credentials', () async {
    final gateway = OpdsHttpClient(clientFactory: () => MockClient((_) async => http.Response('private', 401)));
    await expectLater(
      gateway.get(catalog, catalog.uri, credentials: credentials),
      throwsA(isA<OpdsException>().having((e) => e.message, 'message', contains('credentials'))),
    );
  });

  test('distinguishes relay connection failures from HTTP failures', () async {
    final gateway = OpdsHttpClient(
      clientFactory: () => MockClient((_) async {
        throw http.ClientException('Failed to fetch');
      }),
    );
    await expectLater(gateway.get(catalog, catalog.uri), throwsA(isA<OpdsConnectionException>()));
    final denied = OpdsHttpClient(clientFactory: () => MockClient((_) async => http.Response('', 403)));
    await expectLater(
      denied.get(catalog, catalog.uri),
      throwsA(isA<OpdsException>().having((error) => error is OpdsConnectionException, 'connection failure', isFalse)),
    );
  });

  test('rejects unsafe and credential-bearing resource URLs', () async {
    final gateway = OpdsHttpClient();
    for (final url in ['file:///etc/passwd', 'https://reader:secret@books.test/opds']) {
      await expectLater(gateway.get(catalog, Uri.parse(url)), throwsA(isA<OpdsException>()));
    }
  });

  test('enforces response size and reports progress', () async {
    final gateway = OpdsHttpClient(
      clientFactory: () =>
          MockClient((_) async => http.Response('12345', 200, headers: {'x-opds-url': catalog.uri.toString()})),
    );
    await expectLater(gateway.get(catalog, catalog.uri, maxBytes: 4), throwsA(isA<OpdsException>()));
    final progress = <int>[];
    await gateway.get(catalog, catalog.uri, onProgress: (received, total) => progress.add(received));
    expect(progress.last, 5);
  });

  test('cancelled operations cannot start requests', () async {
    final cancellation = OpdsCancellation()..cancel();
    await expectLater(
      OpdsHttpClient().get(catalog, catalog.uri, cancellation: cancellation),
      throwsA(isA<OpdsCancelled>()),
    );
  });
}
