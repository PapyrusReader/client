import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';

class AuthApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  const AuthApiException({required this.statusCode, required this.message, this.code});

  @override
  String toString() => message;
}

class AuthApiClient {
  final PapyrusApiConfig config;
  final http.Client _httpClient;

  AuthApiClient({required this.config, http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  Uri googleOAuthStartUri(String redirectUri) {
    return config.endpoint('/auth/oauth/google/start', {'redirect_uri': redirectUri});
  }

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String displayName,
    String clientType = 'mobile',
    String? deviceLabel,
  }) async {
    final json = await _postJson(
      config.endpoint('/auth/register'),
      body: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'client_type': clientType,
        'device_label': deviceLabel,
      },
    );

    return AuthTokens.fromJson(json);
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
    String clientType = 'mobile',
    String? deviceLabel,
  }) async {
    final json = await _postJson(
      config.endpoint('/auth/login'),
      body: {'email': email, 'password': password, 'client_type': clientType, 'device_label': deviceLabel},
    );

    return AuthTokens.fromJson(json);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _postJson(config.endpoint('/auth/refresh'), body: {'refresh_token': refreshToken});

    return AuthTokens.fromJson(json);
  }

  Future<AuthTokens> exchangeCode({required String code, String clientType = 'mobile', String? deviceLabel}) async {
    final json = await _postJson(
      config.endpoint('/auth/exchange-code'),
      body: {'code': code, 'client_type': clientType, 'device_label': deviceLabel},
    );

    return AuthTokens.fromJson(json);
  }

  Future<void> logout(String accessToken) async {
    await _postJson(config.endpoint('/auth/logout'), accessToken: accessToken);
  }

  Future<PapyrusUser> currentUser(String accessToken) async {
    final json = await _getJson(config.endpoint('/users/me'), accessToken: accessToken);

    return PapyrusUser.fromJson(json);
  }

  Future<PapyrusUser> updateCurrentUser({required String accessToken, String? displayName, String? avatarUrl}) async {
    final body = <String, Object?>{};

    if (displayName != null) {
      body['display_name'] = displayName;
    }

    if (avatarUrl != null) {
      body['avatar_url'] = avatarUrl;
    }

    final json = await _patchJson(config.endpoint('/users/me'), accessToken: accessToken, body: body);

    return PapyrusUser.fromJson(json);
  }

  Future<String> forgotPassword(String email) async {
    final json = await _postJson(config.endpoint('/auth/forgot-password'), body: {'email': email});

    return json['message'] as String? ?? 'If the email is registered, a reset link has been sent';
  }

  Future<String> resetPassword({required String token, required String password}) async {
    final json = await _postJson(config.endpoint('/auth/reset-password'), body: {'token': token, 'password': password});

    return json['message'] as String? ?? 'Password has been reset successfully';
  }

  Future<String> verifyEmail(String token) async {
    final json = await _postJson(config.endpoint('/auth/verify-email'), body: {'token': token});

    return json['message'] as String? ?? 'Email verified successfully';
  }

  Future<String> resendVerification(String email) async {
    final json = await _postJson(config.endpoint('/auth/resend-verification'), body: {'email': email});

    return json['message'] as String? ?? 'If the email is registered, a verification link has been sent';
  }

  Future<PowerSyncToken> powerSyncToken(String accessToken) async {
    final json = await _postJson(config.endpoint('/auth/powersync-token'), accessToken: accessToken);

    return PowerSyncToken.fromJson(json);
  }

  Future<void> uploadPowerSyncBatch(String accessToken, List<Map<String, dynamic>> batch) async {
    await _postJson(config.endpoint('/sync/powersync-upload'), accessToken: accessToken, body: {'batch': batch});
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {String? accessToken}) async {
    final response = await _httpClient.get(uri, headers: _headers(accessToken));

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, {Map<String, Object?>? body, String? accessToken}) async {
    final response = await _httpClient.post(
      uri,
      headers: _headers(accessToken),
      body: body == null ? null : jsonEncode(body),
    );

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _patchJson(
    Uri uri, {
    required String accessToken,
    required Map<String, Object?> body,
  }) async {
    final response = await _httpClient.patch(uri, headers: _headers(accessToken), body: jsonEncode(body));

    return _decodeResponse(response);
  }

  Map<String, String> _headers(String? accessToken) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = decoded['error'];

    if (error is Map<String, dynamic>) {
      throw AuthApiException(
        statusCode: response.statusCode,
        code: error['code'] as String?,
        message: error['message'] as String? ?? 'Authentication request failed',
      );
    }

    throw AuthApiException(statusCode: response.statusCode, message: 'Authentication request failed');
  }
}
