import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';

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
}
