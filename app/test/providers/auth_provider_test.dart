import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test'))),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

  AuthTokens? bootstrapResult;
  Object? bootstrapError;
  AuthTokens? refreshResult;
  Object? refreshError;
  bool clearCalled = false;

  @override
  Future<AuthTokens?> bootstrap() async {
    if (bootstrapError != null) {
      throw bootstrapError!;
    }

    return bootstrapResult;
  }

  @override
  Future<AuthTokens> refresh() async {
    if (refreshError != null) {
      throw refreshError!;
    }

    return refreshResult ?? _tokens('refresh-user');
  }

  @override
  Future<void> clearTokens() async {
    clearCalled = true;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bootstraps signed in state from stored refresh token', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = FakeAuthRepository()..bootstrapResult = _tokens('Bootstrap User');
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);

    await provider.bootstrap();

    expect(provider.isSignedIn, isTrue);
    expect(provider.user?.displayName, 'Bootstrap User');
  });

  test('clears auth state when refresh fails', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = FakeAuthRepository()
      ..bootstrapResult = _tokens('Bootstrap User')
      ..refreshError = const AuthApiException(statusCode: 401, message: 'Invalid refresh token');
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);

    await provider.bootstrap();
    final refreshed = await provider.refresh();

    expect(refreshed, isFalse);
    expect(provider.isSignedIn, isFalse);
    expect(provider.user, isNull);
  });

  test('offline mode clears tokens and bypasses signed in state', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = FakeAuthRepository()..bootstrapResult = _tokens('Bootstrap User');
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);

    await provider.bootstrap();
    provider.setOfflineMode(true);

    expect(provider.isOfflineMode, isTrue);
    expect(provider.isSignedIn, isFalse);
    expect(repository.clearCalled, isTrue);
  });
}

AuthTokens _tokens(String displayName) {
  return AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: '11111111-1111-1111-1111-111111111111',
      email: 'reader@example.com',
      displayName: displayName,
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
    ),
  );
}
