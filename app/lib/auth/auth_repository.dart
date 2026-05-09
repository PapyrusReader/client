import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/platform/web_redirect.dart';

class AuthRepository {
  static const nativeOAuthRedirectUri = 'papyrus://auth/callback';

  final AuthApiClient apiClient;
  final TokenStore tokenStore;

  Future<AuthTokens>? _refreshOperation;

  AuthRepository({required this.apiClient, required this.tokenStore});

  String? get accessToken => tokenStore.accessToken;

  Future<AuthTokens?> bootstrap() async {
    final refreshToken = await tokenStore.readRefreshToken();

    if (refreshToken == null) {
      return null;
    }

    return refresh();
  }

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String displayName,
    required String clientType,
    String? deviceLabel,
  }) async {
    final tokens = await apiClient.register(
      email: email,
      password: password,
      displayName: displayName,
      clientType: clientType,
      deviceLabel: deviceLabel,
    );

    await _save(tokens);
    return tokens;
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
    required String clientType,
    String? deviceLabel,
  }) async {
    final tokens = await apiClient.login(
      email: email,
      password: password,
      clientType: clientType,
      deviceLabel: deviceLabel,
    );

    await _save(tokens);
    return tokens;
  }

  Future<AuthTokens> refresh() {
    _refreshOperation ??= _refresh();
    return _refreshOperation!;
  }

  Future<AuthTokens> _refresh() async {
    try {
      final refreshToken = await tokenStore.readRefreshToken();

      if (refreshToken == null) {
        throw const AuthApiException(statusCode: 401, message: 'No stored refresh token');
      }

      final tokens = await apiClient.refresh(refreshToken);
      await _save(tokens);
      return tokens;
    } catch (_) {
      await tokenStore.clear();
      rethrow;
    } finally {
      _refreshOperation = null;
    }
  }

  Future<AuthTokens?> signInWithGoogle({required String clientType, String? deviceLabel}) async {
    final redirectUri = kIsWeb ? _webOAuthRedirectUri() : nativeOAuthRedirectUri;
    final startUri = apiClient.googleOAuthStartUri(redirectUri);

    if (kIsWeb) {
      redirectTo(startUri.toString());
      return null;
    }

    final callbackUrl = await FlutterWebAuth2.authenticate(url: startUri.toString(), callbackUrlScheme: 'papyrus');
    final callbackUri = Uri.parse(callbackUrl);
    return completeGoogleSignIn(callbackUri, clientType: clientType, deviceLabel: deviceLabel);
  }

  Future<AuthTokens> completeGoogleSignIn(Uri callbackUri, {required String clientType, String? deviceLabel}) async {
    final error = callbackUri.queryParameters['error'];

    if (error != null && error.isNotEmpty) {
      throw AuthApiException(statusCode: 400, message: error);
    }

    final code = callbackUri.queryParameters['code'];

    if (code == null || code.isEmpty) {
      throw const AuthApiException(statusCode: 400, message: 'OAuth callback did not include a code');
    }

    final tokens = await apiClient.exchangeCode(code: code, clientType: clientType, deviceLabel: deviceLabel);

    await _save(tokens);
    return tokens;
  }

  Future<void> logout() async {
    final accessToken = tokenStore.accessToken;

    try {
      if (accessToken != null) {
        await apiClient.logout(accessToken);
      }
    } finally {
      await tokenStore.clear();
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

  Future<String> forgotPassword(String email) {
    return apiClient.forgotPassword(email);
  }

  Future<String> resetPassword({required String token, required String password}) {
    return apiClient.resetPassword(token: token, password: password);
  }

  Future<String> verifyEmail(String token) {
    return apiClient.verifyEmail(token);
  }

  Future<String> resendVerification(String email) {
    return apiClient.resendVerification(email);
  }

  Future<void> clearTokens() {
    return tokenStore.clear();
  }

  Future<String> _requireAccessToken() async {
    final currentAccessToken = tokenStore.accessToken;

    if (currentAccessToken != null) {
      return currentAccessToken;
    }

    final tokens = await refresh();
    return tokens.accessToken;
  }

  Future<void> _save(AuthTokens tokens) {
    return tokenStore.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
  }

  String _webOAuthRedirectUri() {
    final base = Uri.base;

    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/auth/callback',
    ).toString();
  }
}
