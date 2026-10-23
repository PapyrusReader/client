import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';

class _Storage implements RefreshTokenStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  for (final sessionCleared in [false, true]) {
    test('recovery persists a usable session unless it was cleared, cleared=$sessionCleared', () async {
      final storage = _Storage();
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final requests = <http.Request>[];

      final repository = AuthRepository(
        apiClient: AuthApiClient(
          config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
          httpClient: MockClient((request) {
            requests.add(request);
            started.complete();
            return response.future;
          }),
        ),
        tokenStore: TokenStore(storage),
      );

      final recovery = repository.recoverAccount(
        AccountDeletionAuthorization(
          token: 'restricted-token',
          userId: 'user',
          email: 'reader@example.com',
          deletionPending: true,
          deletionDueAt: DateTime.now().add(const Duration(days: 30)),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
        clientType: 'web',
        deviceLabel: 'flutter-web',
      );

      await started.future;

      if (sessionCleared) {
        await repository.clearTokens();
      }

      response.complete(
        http.Response(
          jsonEncode({
            'access_token': 'restored-access',
            'refresh_token': 'restored-refresh',
            'expires_in': 3600,
            'user': {
              'user_id': 'user',
              'connected_providers': ['google'],
            },
          }),
          200,
        ),
      );

      if (sessionCleared) {
        await expectLater(recovery, throwsA(isA<AuthApiException>()));
        expect(repository.tokenStore.accessToken, isNull);
        expect(storage.value, isNull);
      } else {
        expect((await recovery).user.userId, 'user');
        expect(repository.tokenStore.accessToken, 'restored-access');
        expect(await repository.tokenStore.readRefreshToken(), 'restored-refresh');
      }

      expect(requests.single.url.path, '/v1/account-deletion/cancel');
      expect(jsonDecode(requests.single.body), {
        'authorization_token': 'restricted-token',
        'client_type': 'web',
        'device_label': 'flutter-web',
      });
    });
  }
}
