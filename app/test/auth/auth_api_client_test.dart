import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/media/media_models.dart';

const _authResponse = {
  'access_token': 'access-token',
  'refresh_token': 'refresh-token',
  'token_type': 'Bearer',
  'expires_in': 3600,
  'user': {
    'user_id': '11111111-1111-1111-1111-111111111111',
    'email': 'reader@example.com',
    'display_name': 'Reader',
    'avatar_url': null,
    'email_verified': false,
    'created_at': '2026-05-09T12:00:00Z',
    'last_login_at': null,
  },
};

void main() {
  test('login maps Papyrus token response', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'reader@example.com',
          'password': 'password123',
          'client_type': 'mobile',
          'device_label': 'test-device',
        });

        return http.Response(jsonEncode(_authResponse), 200);
      }),
    );

    final tokens = await client.login(
      email: 'reader@example.com',
      password: 'password123',
      clientType: 'mobile',
      deviceLabel: 'test-device',
    );

    expect(tokens.accessToken, 'access-token');
    expect(tokens.refreshToken, 'refresh-token');
    expect(tokens.user.displayName, 'Reader');
  });

  test('throws AuthApiException for server errors', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid email or password'},
          }),
          401,
        );
      }),
    );

    await expectLater(
      client.login(email: 'reader@example.com', password: 'wrong'),
      throwsA(isA<AuthApiException>().having((error) => error.message, 'message', 'Invalid email or password')),
    );
  });

  test('googleOAuthStartUri builds server-owned browser flow URL', () {
    final client = AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')));

    final uri = client.googleOAuthStartUri('papyrus://auth/callback');

    expect(uri.path, '/v1/auth/oauth/google/start');
    expect(uri.queryParameters['redirect_uri'], 'papyrus://auth/callback');
  });

  test('ensureServerReachable maps network failures to auth errors before OAuth redirect', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/health');
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    await expectLater(
      client.ensureServerReachable(),
      throwsA(
        isA<AuthApiException>().having((error) => error.message, 'message', 'Unable to connect. Please try again.'),
      ),
    );
  });

  test('powerSyncToken maps Papyrus token response', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/powersync-token');
        expect(request.headers['Authorization'], 'Bearer access-token');

        return http.Response(jsonEncode({'token': 'powersync-token', 'expires_in': 300}), 200);
      }),
    );

    final token = await client.powerSyncToken('access-token');

    expect(token.token, 'powersync-token');
    expect(token.expiresIn, 300);
  });

  test('uploadPowerSyncBatch posts PowerSync mutations', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/sync/powersync-upload');
        expect(request.headers['Authorization'], 'Bearer access-token');
        expect(jsonDecode(request.body), {
          'batch': [
            {
              'type': 'books',
              'op': 'PUT',
              'id': 'book-id',
              'data': {'title': 'Book'},
            },
          ],
        });

        return http.Response(jsonEncode({'applied_count': 1}), 200);
      }),
    );

    await client.uploadPowerSyncBatch('access-token', [
      {
        'type': 'books',
        'op': 'PUT',
        'id': 'book-id',
        'data': {'title': 'Book'},
      },
    ]);
  });

  test('fetchMediaUsage maps storage usage response', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/media/usage');
        expect(request.headers['Authorization'], 'Bearer access-token');

        return http.Response(jsonEncode({'used_bytes': 10, 'quota_bytes': 100, 'available_bytes': 90}), 200);
      }),
    );

    final usage = await client.fetchMediaUsage('access-token');

    expect(usage.usedBytes, 10);
    expect(usage.quotaBytes, 100);
    expect(usage.availableBytes, 90);
  });

  test('downloadMedia returns authenticated bytes', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/media/asset-id');
        expect(request.headers['Authorization'], 'Bearer access-token');

        return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'application/epub+zip'});
      }),
    );

    final bytes = await client.downloadMedia('access-token', 'asset-id');

    expect(bytes, Uint8List.fromList([1, 2, 3]));
  });

  test('uploadMedia sends authenticated multipart media request', () async {
    final client = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
      httpClient: _CapturingMultipartClient((request, body) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/media');
        expect(request.headers['Authorization'], 'Bearer access-token');
        expect(request.headers['content-type'], contains('multipart/form-data'));
        expect(body, contains('name="book_id"'));
        expect(body, contains('11111111-1111-1111-1111-111111111111'));
        expect(body, contains('name="kind"'));
        expect(body, contains('book_file'));
        expect(body, contains('filename="book.epub"'));
        expect(body, contains('epub bytes'));

        return http.Response(
          jsonEncode({
            'asset_id': '22222222-2222-2222-2222-222222222222',
            'owner_user_id': '33333333-3333-3333-3333-333333333333',
            'book_id': '11111111-1111-1111-1111-111111111111',
            'kind': 'book_file',
            'original_filename': 'book.epub',
            'content_type': 'application/epub+zip',
            'extension': 'epub',
            'size_bytes': 10,
            'sha256': 'hash',
            'storage_path': 'path',
          }),
          201,
        );
      }),
    );

    final asset = await client.uploadMedia(
      'access-token',
      MediaUploadPayload(
        bookId: '11111111-1111-1111-1111-111111111111',
        kind: MediaKind.bookFile,
        filename: 'book.epub',
        contentType: 'application/epub+zip',
        bytes: Uint8List.fromList('epub bytes'.codeUnits),
      ),
    );

    expect(asset.assetId, '22222222-2222-2222-2222-222222222222');
    expect(asset.kind, MediaKind.bookFile);
  });
}

class _CapturingMultipartClient extends http.BaseClient {
  _CapturingMultipartClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request, String body) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final response = await handler(request, body);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
