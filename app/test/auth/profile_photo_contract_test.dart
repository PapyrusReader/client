import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider_test.dart' show FakeAuthRepository, MemoryRefreshTokenStorage;

const _avatarUrl = '/users/me/avatar/11111111-1111-1111-1111-111111111111';
const _userJson = {
  'user_id': 'reader',
  'email': 'reader@example.com',
  'display_name': 'Reader',
  'avatar_url': _avatarUrl,
  'email_verified': true,
  'connected_providers': <String>[],
};

class _DelayedRepository extends FakeAuthRepository {
  final saved = Completer<PapyrusUser>();

  @override
  Future<PapyrusUser> uploadProfilePhoto(Uint8List bytes, {required String displayName}) => saved.future;
}

void main() {
  test('photo upload and download retry with refreshed credentials', () async {
    for (final uploading in [true, false]) {
      var attempts = 0;
      var refreshes = 0;
      final store = TokenStore(MemoryRefreshTokenStorage());
      await store.saveTokens(accessToken: 'expired-access', refreshToken: 'refresh');

      final repository = AuthRepository(
        tokenStore: store,
        apiClient: AuthApiClient(
          config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/auth/refresh') {
              refreshes++;
              return http.Response(
                jsonEncode({
                  'access_token': 'fresh-access',
                  'refresh_token': 'fresh-refresh',
                  'token_type': 'Bearer',
                  'expires_in': 3600,
                  'user': _userJson,
                }),
                200,
              );
            }

            attempts++;

            if (attempts == 1) {
              return http.Response(
                jsonEncode({
                  'error': {'message': 'Expired'},
                }),
                401,
              );
            }

            expect(request.headers['Authorization'], 'Bearer fresh-access');
            return uploading ? http.Response(jsonEncode(_userJson), 200) : http.Response.bytes([1, 2, 3], 200);
          }),
        ),
      );

      if (uploading) {
        expect((await repository.uploadProfilePhoto(Uint8List(3), displayName: 'Reader')).avatarUrl, _avatarUrl);
      } else {
        expect(await repository.downloadProfilePhoto(_avatarUrl), [1, 2, 3]);
      }

      expect(attempts, 2);
      expect(refreshes, 1);
    }
  });

  test('an upload completing after a server switch does not replace the active profile', () async {
    SharedPreferences.setMockInitialValues({});
    final tokens = AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'Bearer',
      expiresIn: 3600,
      user: PapyrusUser.fromJson(_userJson),
    );

    final repository = _DelayedRepository()..bootstrapResult = tokens;
    final provider = AuthProvider(
      await SharedPreferences.getInstance(),
      repository: repository,
      bootstrapOnCreate: false,
    );
    addTearDown(provider.dispose);
    await provider.bootstrap();
    final saved = provider.updateProfile(displayName: 'New name', photoBytes: Uint8List(3));
    await provider.replaceRepository(FakeAuthRepository(), bootstrapNewRepository: false);
    repository.saved.complete(tokens.user);
    expect(await saved, isFalse);
    expect(provider.user, isNull);
    expect(provider.isSignedIn, isFalse);
  });
}
