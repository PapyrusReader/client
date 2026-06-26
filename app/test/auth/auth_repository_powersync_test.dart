import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
  String? value;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String refreshToken) async {
    value = refreshToken;
  }
}

void main() {
  test('createPowerSyncToken refreshes Papyrus auth once after 401', () async {
    var powerSyncTokenCalls = 0;
    final store = TokenStore(MemoryRefreshTokenStorage());
    await store.saveTokens(accessToken: 'expired-access', refreshToken: 'refresh-token');
    final repository = AuthRepository(
      apiClient: AuthApiClient(
        config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/powersync-token') {
            powerSyncTokenCalls += 1;

            if (powerSyncTokenCalls == 1) {
              return http.Response(
                jsonEncode({
                  'error': {'message': 'Expired'},
                }),
                401,
              );
            }

            expect(request.headers['Authorization'], 'Bearer fresh-access');
            return http.Response(jsonEncode({'token': 'powersync-token', 'expires_in': 300}), 200);
          }

          if (request.url.path == '/v1/auth/refresh') {
            expect(jsonDecode(request.body), {'refresh_token': 'refresh-token'});
            return http.Response(jsonEncode(_authResponse), 200);
          }

          throw StateError('Unexpected request: ${request.url}');
        }),
      ),
      tokenStore: store,
    );

    final token = await repository.createPowerSyncToken();

    expect(token.token, 'powersync-token');
    expect(powerSyncTokenCalls, 2);
    expect(store.accessToken, 'fresh-access');
  });
}

const _authResponse = {
  'access_token': 'fresh-access',
  'refresh_token': 'fresh-refresh',
  'token_type': 'Bearer',
  'expires_in': 3600,
  'user': {
    'user_id': '11111111-1111-1111-1111-111111111111',
    'email': 'reader@example.com',
    'display_name': 'Reader',
    'avatar_url': null,
    'email_verified': true,
    'created_at': null,
    'last_login_at': null,
  },
};
