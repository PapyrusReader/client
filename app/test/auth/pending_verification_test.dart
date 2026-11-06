import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStorage implements RefreshTokenStorage {
  String? value;
  int writes = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<String?> read() async {
    await readGate?.future;
    return value;
  }

  @override
  Future<void> delete() async => value = null;

  @override
  Future<void> write(String refreshToken) async {
    writes += 1;
    writeStarted?.complete();
    await writeGate?.future;
    value = refreshToken;
  }
}

Map<String, Object?> tokens({bool verified = true, String user = 'alice'}) => {
  'access_token': 'access-$user',
  'refresh_token': 'refresh-$user',
  'expires_in': 3600,
  'user': {
    'user_id': user,
    'email': '$user@example.com',
    'display_name': user,
    'email_verified': verified,
    'connected_providers': <String>[],
  },
};

http.Response response(Object body, [int status = 200, Map<String, String>? headers]) =>
    http.Response(jsonEncode(body), status, headers: headers ?? {});

http.Response verificationRequired({int cooldown = 0}) => response({
  'error': {
    'code': 'EMAIL_VERIFICATION_REQUIRED',
    'message': 'Verify your email address before signing in.',
    'details': {'email': 'alice@example.com', 'resend_after': cooldown},
  },
}, 403);

AuthRepository repository(
  Future<http.Response> Function(http.Request) handler, {
  MemoryStorage? storage,
  String server = 'one',
}) => AuthRepository(
  apiClient: AuthApiClient(
    config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://$server.example.test'), apiPrefix: '/custom/api'),
    httpClient: MockClient(handler),
  ),
  tokenStore: TokenStore(storage ?? MemoryStorage()),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cancelled bootstrap cannot refresh after a delayed secure-storage read', () async {
    final storage = MemoryStorage()
      ..value = 'old-refresh'
      ..readGate = Completer<void>();
    final repo = repository((_) async => fail('Cancelled bootstrap must not refresh'), storage: storage);
    final bootstrap = repo.bootstrap();
    final rejected = expectLater(bootstrap, throwsA(isA<AuthApiException>()));
    repo.cancelPendingAuthentication();
    storage.readGate!.complete();
    await rejected;
    expect(storage.value, 'old-refresh');
    expect(storage.writes, 0);
  });

  test('pending registration preserves guest state and persists no credentials across restart', () async {
    final storage = MemoryStorage();
    final repo = repository((request) async {
      expect(request.url.path, '/custom/api/auth/register');
      return response({
        'status': 'verification_required',
        'email': 'alice@example.com',
        'message': 'Check your email',
        'resend_after': 60,
      }, 201);
    }, storage: storage);
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthProvider(prefs, repository: repo, bootstrapOnCreate: false);
    auth.setOfflineMode(true);
    expect(await auth.register(email: 'Alice@example.com', password: 'password', displayName: 'Alice'), isTrue);
    expect(auth.pendingVerification?.email, 'alice@example.com');
    expect(auth.isOfflineMode, isTrue);
    expect(auth.user, isNull);
    expect(auth.isSignedIn, isFalse);
    expect(storage.writes, 0);
    expect(await repo.bootstrap(), isNull);
    auth.dispose();
    final restarted = AuthProvider(prefs, repository: repo, bootstrapOnCreate: false);
    await restarted.bootstrap();
    expect(restarted.pendingVerification, isNull);
    expect(restarted.isOfflineMode, isTrue);
    restarted.dispose();
  });

  test('verified sign-in alone stores tokens and leaves guest mode', () async {
    final storage = MemoryStorage();
    final repo = repository((_) async => response(tokens()), storage: storage);
    final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
    auth.setOfflineMode(true);
    expect(await auth.login(email: 'alice@example.com', password: 'password'), isTrue);
    expect(auth.isSignedIn, isTrue);
    expect(auth.isOfflineMode, isFalse);
    expect(storage.value, 'refresh-alice');
    auth.dispose();
  });

  for (final operation in ['login', 'google', 'refresh', 'sync']) {
    test('$operation verification-required response never installs credentials', () async {
      final storage = MemoryStorage();
      var denying = false;
      final repo = repository(
        (request) async => denying ? verificationRequired(cooldown: 12) : response(tokens()),
        storage: storage,
      );
      final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);

      if (operation == 'refresh' || operation == 'sync') {
        await auth.login(email: 'alice@example.com', password: 'password');
      }

      denying = true;
      switch (operation) {
        case 'login':
          expect(await auth.login(email: 'alice@example.com', password: 'password'), isFalse);
        case 'google':
          expect(await auth.completeGoogleSignIn(Uri.parse('papyrus://auth/callback?code=pending-once')), isFalse);
        case 'refresh':
          expect(await auth.refresh(), isFalse);
        case 'sync':
          await expectLater(repo.createPowerSyncToken(), throwsA(isA<AuthApiException>()));
      }

      expect(auth.isSignedIn, isFalse);
      expect(auth.pendingVerification?.resendAfter, 12);
      expect(storage.value, isNull);
      expect(repo.tokenStore.accessToken, isNull);
      expect(auth.hasOfflineAccount, operation == 'refresh' || operation == 'sync');
      auth.dispose();
    });
  }

  test('old-server unverified tokens are revoked before any storage', () async {
    final paths = <String>[];
    final storage = MemoryStorage();
    final repo = repository((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      return response(tokens(verified: false));
    }, storage: storage);
    await expectLater(
      repo.login(email: 'alice@example.com', password: 'password', clientType: 'web'),
      throwsA(isA<AuthApiException>()),
    );
    expect(paths, ['/custom/api/auth/login', '/custom/api/auth/logout']);
    expect(storage.writes, 0);
    final pending = await repo.register(
      email: 'alice@example.com',
      password: 'password',
      displayName: 'Alice',
      clientType: 'web',
    );
    expect(pending.email, 'alice@example.com');
    expect(storage.writes, 0);
  });

  test('malformed pending and token payloads are rejected', () async {
    for (final body in [
      {'status': 'verification_required', 'email': 'alice@example.com', 'message': 'Check email', 'resend_after': -1},
      {'status': 'verification_required', 'resend_after': 60},
      {
        'status': 'verification_required',
        'email': 'alice@example.com',
        'message': 'Check email',
        'resend_after': 0,
        'refresh_token': 'secret',
      },
    ]) {
      final storage = MemoryStorage();
      final repo = repository((_) async => response(body, 201), storage: storage);
      await expectLater(
        repo.register(email: 'alice@example.com', password: 'password', displayName: 'Alice', clientType: 'web'),
        throwsA(isA<FormatException>()),
      );
      expect(storage.writes, 0);
    }
  });

  for (final cancel in ['guest', 'server', 'cancel', 'signout']) {
    test('$cancel discards delayed sign-in and pending responses', () async {
      for (final registration in [false, true]) {
        final reply = Completer<http.Response>();
        final started = Completer<void>();
        final storage = MemoryStorage();
        final repo = repository((_) {
          started.complete();
          return reply.future;
        }, storage: storage);
        final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
        final pending = registration
            ? auth.register(email: 'alice@example.com', password: 'password', displayName: 'Alice')
            : auth.login(email: 'alice@example.com', password: 'password');
        await started.future;
        switch (cancel) {
          case 'guest':
            auth.setOfflineMode(true);
          case 'server':
            await auth.replaceRepository(
              repository((_) async => response(tokens(user: 'bob')), server: 'two'),
              bootstrapNewRepository: false,
            );
          case 'cancel':
            auth.cancelAuthentication();
          case 'signout':
            await auth.signOut();
        }
        reply.complete(
          registration
              ? response({
                  'status': 'verification_required',
                  'email': 'alice@example.com',
                  'message': 'Check email',
                  'resend_after': 60,
                }, 201)
              : response(tokens()),
        );
        expect(await pending, isFalse);
        expect(auth.user, isNull);
        expect(auth.pendingVerification, isNull);
        expect(storage.value, isNull);
        auth.dispose();
      }
    });
  }

  test('cancellation during secure storage write removes the stale credentials', () async {
    final storage = MemoryStorage()
      ..writeGate = Completer<void>()
      ..writeStarted = Completer<void>();
    final repo = repository((_) async => response(tokens()), storage: storage);
    final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
    final login = auth.login(email: 'alice@example.com', password: 'password');
    await storage.writeStarted!.future;
    auth.cancelAuthentication();
    storage.writeGate!.complete();
    expect(await login, isFalse);
    expect(storage.value, isNull);
    expect(repo.tokenStore.accessToken, isNull);
    auth.dispose();
  });

  test('pending Google handoff is consumed once and verification requires a fresh sign-in', () async {
    var exchanges = 0;
    final storage = MemoryStorage();
    final repo = repository((request) async {
      if (request.url.path.endsWith('/verify-email')) {
        return response({'message': 'Email verified successfully'});
      }

      exchanges += 1;
      if (exchanges == 1) {
        return verificationRequired();
      }

      if (jsonDecode(request.body)['code'] == 'pending') {
        return response({
          'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid code', 'details': {}},
        }, 401);
      }

      return response(tokens());
    }, storage: storage);
    final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
    expect(await auth.completeGoogleSignIn(Uri.parse('papyrus://auth/callback?code=pending')), isFalse);
    expect(await auth.verifyEmail('verification-token'), isNotNull);
    expect(storage.value, isNull);
    expect(await auth.completeGoogleSignIn(Uri.parse('papyrus://auth/callback?code=pending')), isFalse);
    expect(await auth.completeGoogleSignIn(Uri.parse('papyrus://auth/callback?code=fresh')), isTrue);
    auth.dispose();
  });

  for (final error in ['email_required', 'verification_unavailable', 'account_exists', 'access_denied']) {
    test('Google $error gives actionable guidance without exchange', () async {
      final repo = repository((_) async => fail('No request expected'));
      final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
      expect(await auth.completeGoogleSignIn(Uri.parse('papyrus://auth/callback?error=$error')), isFalse);
      expect(auth.error, isNot(error));
      expect(auth.isSignedIn, isFalse);
      auth.dispose();
    });
  }

  test('registration delivery failure reports the failed action and retains retry timing', () async {
    final repo = repository(
      (_) async => response(
        {
          'error': {'code': 'VERIFICATION_UNAVAILABLE', 'message': 'Please try later', 'details': {}},
        },
        503,
        {'retry-after': '60'},
      ),
    );
    final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
    expect(await auth.register(email: 'alice@example.com', password: 'password', displayName: 'Alice'), isFalse);
    expect(auth.error, 'Registration failed. Please try again.');
    expect(auth.retryAt!.isAfter(DateTime.now()), isTrue);
    expect(auth.isSignedIn, isFalse);
    auth.dispose();
  });

  test('resend parses cooldown and delivery failures preserve retry headers', () async {
    var requests = 0;
    final repo = repository((_) async {
      requests += 1;
      if (requests == 1) {
        return response({
          'message': 'If the email is registered, a verification link has been sent',
          'resend_after': 60,
        });
      }

      return response(
        {
          'error': {'code': 'VERIFICATION_UNAVAILABLE', 'message': 'Please try later', 'details': {}},
        },
        503,
        {'retry-after': '60'},
      );
    });
    final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
    expect(await auth.resendVerification('alice@example.com'), isNotNull);
    expect(await auth.resendVerification('alice@example.com'), isNull);
    expect(requests, 1);
    auth.cancelAuthentication();
    expect(await auth.resendVerification('alice@example.com'), isNull);
    expect(auth.retryAt!.isAfter(DateTime.now()), isTrue);
    expect(auth.errorCode, 'VERIFICATION_UNAVAILABLE');
    expect(auth.error, AuthApiClient.verificationUnavailableMessage);
    auth.dispose();
  });
}
