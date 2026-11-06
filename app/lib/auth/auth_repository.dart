import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/platform/web_redirect.dart';

class AuthRepository {
  static const nativeOAuthRedirectUri = 'papyrus://auth/callback';
  static const desktopOAuthRedirectUri = 'http://localhost:43821/auth/callback';

  final AuthApiClient apiClient;
  final TokenStore tokenStore;

  Future<AuthTokens>? _refreshOperation;
  int _tokenGeneration = 0;
  Future<void> _credentialOperation = Future<void>.value();
  void Function(AuthApiException error)? onVerificationRequired;

  void cancelPendingAuthentication() {
    _tokenGeneration += 1;
    _refreshOperation = null;
  }

  AuthRepository({required this.apiClient, required this.tokenStore});

  bool get _usesDesktopLoopbackOAuth {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<AuthTokens?> bootstrap() async {
    final generation = _tokenGeneration;
    final refreshToken = await tokenStore.readRefreshToken();
    _requireGeneration(generation);

    if (refreshToken == null) {
      return null;
    }

    return refresh();
  }

  Future<PendingVerification> register({
    required String email,
    required String password,
    required String displayName,
    required String clientType,
    String? deviceLabel,
  }) {
    cancelPendingAuthentication();
    return apiClient.register(
      email: email,
      password: password,
      displayName: displayName,
      clientType: clientType,
      deviceLabel: deviceLabel,
    );
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
    required String clientType,
    String? deviceLabel,
  }) async {
    final generation = ++_tokenGeneration;

    final tokens = await apiClient.login(
      email: email,
      password: password,
      clientType: clientType,
      deviceLabel: deviceLabel,
    );

    await _save(tokens, generation);
    return tokens;
  }

  Future<AuthTokens> refresh() {
    final pending = _refreshOperation;

    if (pending != null) {
      return pending;
    }

    final operation = _refresh();
    _refreshOperation = operation;

    return operation.whenComplete(() {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
      }
    });
  }

  Future<AuthTokens> _refresh() async {
    final generation = _tokenGeneration;

    try {
      final refreshToken = await tokenStore.readRefreshToken();

      if (refreshToken == null) {
        throw const AuthApiException(statusCode: 401, message: 'No stored refresh token');
      }

      final tokens = await apiClient.refresh(refreshToken);

      if (generation != _tokenGeneration) {
        throw const AuthApiException(statusCode: 401, message: 'Session has ended');
      }

      await _save(tokens, generation);
      return tokens;
    } catch (error) {
      if (generation == _tokenGeneration) {
        await clearTokens();

        if (error is AuthApiException && error.code == 'EMAIL_VERIFICATION_REQUIRED') {
          onVerificationRequired?.call(error);
        }
      }

      rethrow;
    }
  }

  Future<AuthTokens?> signInWithGoogle({required String clientType, String? deviceLabel}) async {
    final generation = ++_tokenGeneration;
    await apiClient.ensureServerReachable();

    final redirectUri = switch (kIsWeb) {
      true => _webOAuthRedirectUri(),
      false when _usesDesktopLoopbackOAuth => desktopOAuthRedirectUri,
      false => nativeOAuthRedirectUri,
    };

    _requireGeneration(generation);
    final startUri = apiClient.googleOAuthStartUri(redirectUri);

    if (kIsWeb) {
      rememberOAuthServer('${apiClient.config.apiBaseUri}');
      redirectTo(startUri.toString());
      return null;
    }

    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: startUri.toString(),
      callbackUrlScheme: _usesDesktopLoopbackOAuth ? desktopOAuthRedirectUri : Uri.parse(nativeOAuthRedirectUri).scheme,
      options: const FlutterWebAuth2Options(useWebview: false),
    );

    _requireGeneration(generation);
    final callbackUri = Uri.parse(callbackUrl);
    return completeGoogleSignIn(callbackUri, clientType: clientType, deviceLabel: deviceLabel);
  }

  Future<AuthTokens> completeGoogleSignIn(Uri callbackUri, {required String clientType, String? deviceLabel}) async {
    final generation = ++_tokenGeneration;

    if (!consumeOAuthServer('${apiClient.config.apiBaseUri}')) {
      throw const AuthApiException(
        statusCode: 400,
        message: 'The sign-in server changed or the callback expired. Start a new Google sign-in.',
      );
    }

    final error = callbackUri.queryParameters['error'];

    if (error != null && error.isNotEmpty) {
      throw AuthApiException(
        statusCode: 400,
        code: error,
        message: switch (error) {
          'email_required' =>
            'Google did not provide an email address. Register with email, or contact your server operator for an existing account.',
          'verification_unavailable' => AuthApiClient.verificationUnavailableMessage,
          'account_exists' =>
            'An account with this email already exists. Sign in to that account before linking Google.',
          'access_denied' => 'Google sign-in was cancelled. You can try again.',
          _ => 'Google sign-in could not be completed. Please start a new sign-in.',
        },
      );
    }

    final code = callbackUri.queryParameters['code'];

    if (code == null || code.isEmpty) {
      throw const AuthApiException(statusCode: 400, message: 'OAuth callback did not include a code');
    }

    final tokens = await apiClient.exchangeCode(code: code, clientType: clientType, deviceLabel: deviceLabel);
    await _save(tokens, generation);
    return tokens;
  }

  Future<DateTime> deleteAccount() => _withFreshAccessToken(apiClient.deleteAccount);

  Future<AuthTokens> recoverAccount(
    AccountDeletionAuthorization authorization, {
    required String clientType,
    String? deviceLabel,
  }) async {
    final generation = _tokenGeneration;

    final tokens = await apiClient.recoverAccount(
      authorization,
      clientType: clientType,
      deviceLabel: deviceLabel,
    );

    if (generation != _tokenGeneration) {
      throw const AuthApiException(statusCode: 401, message: 'Session changed. Please sign in again.');
    }

    await _save(tokens, generation);
    return tokens;
  }

  Future<void> logout() async {
    final accessToken = tokenStore.accessToken;
    await clearTokens();

    if (accessToken != null) {
      await apiClient.logout(accessToken);
    }
  }

  Future<PapyrusUser> currentUser() async {
    final accessToken = await _requireAccessToken();
    return apiClient.currentUser(accessToken);
  }

  Future<PapyrusUser> updateCurrentUser({String? displayName, String? avatarUrl}) async {
    final accessToken = await _requireAccessToken();
    return apiClient.updateCurrentUser(accessToken: accessToken, displayName: displayName, avatarUrl: avatarUrl);
  }

  Future<PapyrusUser> uploadProfilePhoto(Uint8List bytes, {required String displayName}) {
    return _withFreshAccessToken((accessToken) {
      return apiClient.uploadProfilePhoto(accessToken, bytes, displayName: displayName);
    });
  }

  Future<Uint8List> downloadProfilePhoto(String avatarUrl) {
    return _withFreshAccessToken((accessToken) => apiClient.downloadProfilePhoto(accessToken, avatarUrl));
  }

  Future<String> forgotPassword(String email) {
    return apiClient.forgotPassword(email);
  }

  Future<String> resetPassword({required String token, required String password}) {
    return apiClient.resetPassword(token: token, password: password);
  }

  Future<String> verifyEmail(String token) {
    return apiClient.verifyEmail(token);
  }

  Future<VerificationDelivery> resendVerification(String email) {
    return apiClient.resendVerification(email);
  }

  Future<PowerSyncToken> createPowerSyncToken() {
    return _withFreshAccessToken((accessToken) {
      return apiClient.powerSyncToken(accessToken);
    });
  }

  Future<void> uploadPowerSyncBatch(List<Map<String, dynamic>> batch) {
    return _withFreshAccessToken((accessToken) {
      return apiClient.uploadPowerSyncBatch(accessToken, batch);
    });
  }

  Future<MediaStorageUsage> fetchMediaUsage() {
    return _withFreshAccessToken((accessToken) {
      return apiClient.fetchMediaUsage(accessToken);
    });
  }

  Future<MediaAsset> uploadMedia(MediaUploadPayload payload) {
    return _withFreshAccessToken((accessToken) {
      return apiClient.uploadMedia(accessToken, payload);
    });
  }

  Future<Uint8List> downloadMedia(String assetId) {
    return _withFreshAccessToken((accessToken) {
      return apiClient.downloadMedia(accessToken, assetId);
    });
  }

  Future<void> deleteMedia(String assetId) {
    return _withFreshAccessToken((accessToken) {
      return apiClient.deleteMedia(accessToken, assetId);
    });
  }

  Future<void> clearTokens() {
    cancelPendingAuthentication();
    return _serializeCredentials(tokenStore.clear);
  }

  Future<T> withFreshAccessToken<T>(Future<T> Function(String accessToken) action) {
    return _withFreshAccessToken(action);
  }

  Future<String> _requireAccessToken() async {
    final currentAccessToken = tokenStore.accessToken;

    if (currentAccessToken != null) {
      return currentAccessToken;
    }

    final tokens = await refresh();
    return tokens.accessToken;
  }

  void _requireGeneration(int generation) {
    if (generation != _tokenGeneration) {
      throw const AuthApiException(statusCode: 401, message: 'Session changed. Please sign in again.');
    }
  }

  Future<void> _serializeCredentials(Future<void> Function() action) {
    final operation = _credentialOperation.then((_) => action());
    _credentialOperation = operation.then<void>((_) {}, onError: (Object error) {});
    return operation;
  }

  Future<void> _save(AuthTokens tokens, int generation) async {
    if (!tokens.user.emailVerified) {
      try {
        await apiClient.logout(tokens.accessToken);
      } catch (_) {
        // The rejected credentials are never persisted.
      }

      throw AuthApiException(
        statusCode: 403,
        code: 'EMAIL_VERIFICATION_REQUIRED',
        message: 'Verify your email address before signing in.',
        pendingVerification: PendingVerification(email: tokens.user.email, resendAfter: 0),
      );
    }

    if (tokens.accessToken.isEmpty ||
        tokens.refreshToken.isEmpty ||
        tokens.user.userId.isEmpty ||
        tokens.expiresIn <= 0) {
      throw const FormatException('Invalid authentication response');
    }

    await _serializeCredentials(() async {
      _requireGeneration(generation);
      await tokenStore.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);

      if (generation != _tokenGeneration) {
        await tokenStore.clear();
        _requireGeneration(generation);
      }
    });
  }

  Future<T> _withFreshAccessToken<T>(Future<T> Function(String accessToken) action) async {
    final generation = _tokenGeneration;

    try {
      try {
        return await action(await _requireAccessToken());
      } on AuthApiException catch (error) {
        if (error.statusCode != 401) {
          rethrow;
        }

        _requireGeneration(generation);
        final tokens = await refresh();
        return await action(tokens.accessToken);
      }
    } on AuthApiException catch (error) {
      if (generation == _tokenGeneration && error.code == 'EMAIL_VERIFICATION_REQUIRED') {
        await clearTokens();
        onVerificationRequired?.call(error);
      }

      rethrow;
    }
  }

  String _webOAuthRedirectUri() {
    return browserAppBaseUri().resolve('auth/callback').toString();
  }
}
