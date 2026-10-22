import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/media/media_models.dart';

void main() {
  final rateLimited = isA<AuthApiException>().having((error) => error.statusCode, 'status', 429);

  test('sync suppresses requests until Retry-After expires without replaying automatically', () async {
    var now = DateTime.utc(2026, 10, 22);
    var requests = 0;

    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
      now: () => now,
      httpClient: MockClient((request) async {
        requests++;
        expect(jsonDecode(request.body), {'batch': []});

        if (requests == 1) {
          return http.Response('rate limited', 429, headers: {'retry-after': '30'});
        }

        return http.Response('{"applied_count":0}', 200);
      }),
    );

    await expectLater(client.uploadPowerSyncBatch('user-a', []), throwsA(rateLimited));
    now = now.add(const Duration(seconds: 5));

    await expectLater(
      client.uploadPowerSyncBatch('user-a', []),
      throwsA(rateLimited.having((error) => error.retryAfter, 'remaining', const Duration(seconds: 25))),
    );

    expect(requests, 1);
    now = now.add(const Duration(seconds: 25));
    expect(requests, 1);
    await client.uploadPowerSyncBatch('user-a', []);
    expect(requests, 2);
  });

  test('media cooldown isolates credentials and endpoints and leaves reads available', () async {
    var mediaRequests = 0;
    var syncRequests = 0;
    var usageRequests = 0;

    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/v1/media':
            mediaRequests++;
            return http.Response('{}', 429, headers: {'retry-after': '60'});
          case '/v1/sync/powersync-upload':
            syncRequests++;
            return http.Response('{"applied_count":0}', 200);
          case '/v1/media/usage':
            usageRequests++;
            return http.Response('{"used_bytes":0,"quota_bytes":100,"available_bytes":100}', 200);
          default:
            throw StateError('Unexpected request');
        }
      }),
    );

    final payload = MediaUploadPayload(
      bookId: 'book',
      kind: MediaKind.bookFile,
      filename: 'book.epub',
      contentType: 'application/epub+zip',
      bytes: Uint8List.fromList([1]),
    );

    await expectLater(client.uploadMedia('user-a', payload), throwsA(rateLimited));
    await expectLater(client.uploadMedia('user-a', payload), throwsA(rateLimited));
    expect(mediaRequests, 1);
    await expectLater(client.uploadMedia('user-b', payload), throwsA(rateLimited));
    expect(mediaRequests, 2);
    await client.uploadPowerSyncBatch('user-a', []);
    await client.fetchMediaUsage('user-a');
    expect(syncRequests, 1);
    expect(usageRequests, 1);
  });

  for (final header in <String?>[null, 'invalid', '-1', 'Thu, 22 Oct 2026 00:01:00 GMT']) {
    test('Retry-After $header uses the expected retry delay', () async {
      final client = AuthApiClient(
        config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
        now: () => DateTime.utc(2026, 10, 22),
        httpClient: MockClient((_) async {
          return http.Response('', 429, headers: {'retry-after': ?header});
        }),
      );

      await expectLater(
        client.uploadPowerSyncBatch('user', []),
        throwsA(rateLimited.having((error) => error.retryAfter, 'retry delay', const Duration(minutes: 1))),
      );
    });
  }
}
