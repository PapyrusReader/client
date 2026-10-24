import 'dart:async';

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
  FakeAuthRepository({AuthApiClient? apiClient})
    : super(
        apiClient: apiClient ?? AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test'))),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

  AuthTokens? bootstrapResult;
  Object? bootstrapError;
  AuthTokens? refreshResult;
  Object? refreshError;
  bool clearCalled = false;
  Completer<void>? clearStarted;
  Completer<void>? clearPause;
  Completer<AuthTokens>? recoveryResult;

  @override
  Future<AuthTokens> recoverAccount(
    AccountDeletionAuthorization authorization, {
    required String clientType,
    String? deviceLabel,
  }) {
    return recoveryResult!.future;
  }

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
    clearStarted?.complete();
    await clearPause?.future;
  }
}

class _DeletionApi extends AuthApiClient {
  _DeletionApi() : super(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test')));

  @override
  Future<DateTime> deleteAccount(String accessToken) async => DateTime.now().add(const Duration(days: 30));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guest deletion rejects duplicate submissions and preserves guest mode on failure', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = AuthProvider(prefs, repository: FakeAuthRepository(), bootstrapOnCreate: false);
    addTearDown(provider.dispose);
    provider.setOfflineMode(true);
    final cleanup = Completer<void>();
    final deletion = provider.deleteGuestAccount(() => cleanup.future);
    expect(provider.isDeletingGuestAccount, isTrue);
    await expectLater(provider.deleteGuestAccount(() async => fail('Duplicate cleanup')), throwsStateError);
    final failure = expectLater(deletion, throwsStateError);
    cleanup.completeError(StateError('Storage failure'));
    await failure;
    expect(provider.isOfflineMode, isTrue);
    expect(provider.isDeletingGuestAccount, isFalse);
  });

  test('guest deletion does not sign out an account selected during cleanup', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = AuthProvider(prefs, repository: FakeAuthRepository(), bootstrapOnCreate: false);
    addTearDown(provider.dispose);
    provider.setOfflineMode(true);
    final cleanup = Completer<void>();
    final deletion = provider.deleteGuestAccount(() => cleanup.future);
    provider.setOfflineMode(false);
    final repository = FakeAuthRepository()..bootstrapResult = _tokens('new-user');
    await provider.replaceRepository(repository);
    final failure = expectLater(deletion, throwsStateError);
    cleanup.complete();
    await failure;
    expect(provider.isSignedIn, isTrue);
    expect(provider.user?.displayName, 'new-user');
    expect(repository.clearCalled, isFalse);
  });

  test('deletion finishing after a server switch preserves the newly selected account', () async {
    final prefs = await SharedPreferences.getInstance();

    final oldRepository = FakeAuthRepository(apiClient: _DeletionApi())
      ..bootstrapResult = _tokens('Old server')
      ..clearStarted = Completer<void>()
      ..clearPause = Completer<void>();

    final newRepository = FakeAuthRepository()..bootstrapResult = _tokens('New server');
    final provider = AuthProvider(prefs, repository: oldRepository, bootstrapOnCreate: false);
    await provider.bootstrap();

    final deletion = provider.deleteAccount();

    await oldRepository.clearStarted!.future;
    await provider.replaceRepository(newRepository);
    oldRepository.clearPause!.complete();
    await deletion;
    expect(provider.isSignedIn, isTrue);
    expect(provider.user?.displayName, 'New server');
    expect(newRepository.clearCalled, isFalse);
    provider.dispose();
  });

  test('recovery finishing after a server switch preserves the newly selected account', () async {
    final prefs = await SharedPreferences.getInstance();
    final oldRepository = FakeAuthRepository()..recoveryResult = Completer<AuthTokens>();
    final newRepository = FakeAuthRepository()..bootstrapResult = _tokens('New server');
    final provider = AuthProvider(prefs, repository: oldRepository, bootstrapOnCreate: false);

    final recovery = provider.recoverAccount(
      AccountDeletionAuthorization(
        token: 'restricted',
        userId: _tokens('Old server').user.userId,
        email: 'reader@example.com',
        deletionPending: true,
        deletionDueAt: DateTime.now().add(const Duration(days: 30)),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );

    await provider.replaceRepository(newRepository);
    oldRepository.recoveryResult!.complete(_tokens('Old server'));
    expect(await recovery, isFalse);
    expect(provider.isSignedIn, isTrue);
    expect(provider.user?.displayName, 'New server');
    provider.dispose();
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

  test('switching auth repository bootstraps the new server session without clearing the old one', () async {
    final prefs = await SharedPreferences.getInstance();
    final officialRepository = FakeAuthRepository()..bootstrapResult = _tokens('Official User');
    final customRepository = FakeAuthRepository()..bootstrapResult = _tokens('Custom User');
    final provider = AuthProvider(prefs, repository: officialRepository, bootstrapOnCreate: false);
    await provider.bootstrap();
    await provider.replaceRepository(customRepository);
    expect(officialRepository.clearCalled, isFalse);
    expect(provider.isSignedIn, isTrue);
    expect(provider.user?.displayName, 'Custom User');
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
