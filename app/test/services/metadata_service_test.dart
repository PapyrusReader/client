import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/services/metadata_service.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/auth_api_client.dart';

void main() {
  for (final source in MetadataSource.values) {
    for (final isIsbn in [false, true]) {
      test('$source paginates ${isIsbn ? 'ISBN' : 'text'} queries with the provider offset', () async {
        final requests = <Uri>[];

        final client = MockClient((request) async {
          requests.add(request.url);

          final body = source == MetadataSource.openLibrary
              ? {
                  'numFound': 24,
                  'docs': [
                    {
                      'title': 'A result',
                      'author_name': ['Author'],
                    },
                  ],
                }
              : {
                  'total_results': 24,
                  'results': [
                    {
                      'title': 'A result',
                      'authors': ['Author'],
                    },
                  ],
                };

          return http.Response(jsonEncode(body), 200);
        });

        addTearDown(client.close);
        final service = MetadataService(client: client);

        for (final page in [1, 2, 3]) {
          final result = isIsbn
              ? await service.searchByIsbn('978-0 141439518', source, page: page)
              : await service.search('Alice & Wonderland', source, page: page);

          expect(result.totalResults, 24);
          expect(result.results.single.title, 'A result');
          expect(result.results.single.source, source);
          final parameters = requests.last.queryParameters;
          final isOpenLibrary = source == MetadataSource.openLibrary;

          if (isOpenLibrary) {
            expect(requests.last.host, 'openlibrary.org');
            expect(parameters['offset'], '${(page - 1) * 10}');
            expect(parameters['limit'], '10');
          } else {
            expect(requests.last.host, 'localhost');
            expect(requests.last.path, '/v1/metadata/google-books');
            expect(parameters['page'], '$page');
            expect(parameters['isbn'], '$isIsbn');
            expect(parameters.containsKey('key'), isFalse);
          }

          final query = isIsbn ? '9780141439518' : 'Alice & Wonderland';
          expect(parameters[isOpenLibrary && isIsbn ? 'isbn' : 'q'], query);
        }
      });
    }
  }

  test('uses the selected server and API prefix with guest requests', () async {
    final requests = <http.Request>[];
    var config = PapyrusApiConfig(serverBaseUri: Uri.parse('https://first.example'), apiPrefix: '/api/v2');

    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"results":[],"total_results":0}', 200);
    });

    final service = MetadataService(
      client: client,
      server: () => MetadataServer(config: config),
    );
    addTearDown(service.close);
    await service.search('Alice', MetadataSource.googleBooks, page: 2);
    expect(requests.single.url.host, 'first.example');
    expect(requests.single.url.path, '/api/v2/metadata/google-books');
    expect(requests.single.headers.containsKey('authorization'), isFalse);
    config = PapyrusApiConfig(serverBaseUri: Uri.parse('https://second.example'));
    await service.search('Alice', MetadataSource.googleBooks);
    expect(requests.last.url.host, 'second.example');
    expect(requests.last.url.queryParameters['key'], isNull);
  });

  test('authenticated requests support token refresh without sending tokens to Open Library', () async {
    final requests = <http.Request>[];
    var authorizations = 0;

    final client = MockClient((request) async {
      requests.add(request);

      if (request.url.host == 'openlibrary.org') {
        return http.Response('{"docs":[]}', 200);
      }

      if (request.headers['authorization'] == 'Bearer expired') {
        return http.Response('{}', 401);
      }

      return http.Response('{"results":[{"title":"Alice","isbn13":"9780141439518","page_count":200}]}', 200);
    });

    final service = MetadataService(
      client: client,
      server: () => MetadataServer(
        config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://selected.example')),
        authorize: (request) async {
          authorizations++;

          try {
            return await request('expired');
          } on AuthApiException catch (error) {
            expect(error.statusCode, 401);
            return request('fresh');
          }
        },
      ),
    );

    addTearDown(service.close);
    final page = await service.search('Alice', MetadataSource.googleBooks);
    expect(page.results.single.pageCount, 200);
    expect(page.results.single.isbn13, '9780141439518');
    expect(requests, hasLength(2));
    expect(requests.every((request) => request.url.host == 'selected.example'), isTrue);
    expect(requests.last.url.path, '/v1/metadata/google-books/authenticated');
    expect(requests.last.headers['authorization'], 'Bearer fresh');
    await service.search('Alice', MetadataSource.openLibrary);
    expect(authorizations, 1);
    expect(requests.last.headers.containsKey('authorization'), isFalse);
  });

  for (final status in [404, 429, 503]) {
    test('Google proxy errors remain actionable: $status', () async {
      final service = MetadataService(client: MockClient((_) async => http.Response('{}', status)));
      addTearDown(service.close);
      await expectLater(service.search('Alice', MetadataSource.googleBooks), throwsA(isA<MetadataSearchException>()));
    });
  }

  test('supports the Open Library documented num_found count and empty final pages', () async {
    final client = MockClient((_) async => http.Response('{"num_found":20,"docs":[]}', 200));
    addTearDown(client.close);
    final result = await MetadataService(client: client).search('Alice', MetadataSource.openLibrary, page: 3);
    expect(result.totalResults, 20);
    expect(result.results, isEmpty);
  });

  test('missing totals remain unknown', () async {
    final client = MockClient((_) async => http.Response('{"results":[]}', 200));
    addTearDown(client.close);
    final result = await MetadataService(client: client).search('Alice', MetadataSource.googleBooks);
    expect(result.totalResults, isNull);
    expect(result.results, isEmpty);
  });

  for (final response in [http.Response('Unavailable', 503), http.Response('invalid json', 200)]) {
    test('failed responses are distinguishable from empty searches: ${response.statusCode}', () async {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      final service = MetadataService(client: client);
      await expectLater(service.search('Alice', MetadataSource.openLibrary), throwsA(isA<Exception>()));
    });
  }
}
