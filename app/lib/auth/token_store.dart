import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class RefreshTokenStorage {
  Future<String?> read();

  Future<void> write(String refreshToken);

  Future<void> delete();
}

class SecureRefreshTokenStorage implements RefreshTokenStorage {
  static const _refreshTokenKey = 'papyrus_refresh_token';

  final FlutterSecureStorage _storage;

  const SecureRefreshTokenStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> write(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<void> delete() => _storage.delete(key: _refreshTokenKey);
}

class TokenStore {
  final RefreshTokenStorage _refreshTokenStorage;

  String? _accessToken;

  TokenStore(this._refreshTokenStorage);

  String? get accessToken => _accessToken;

  bool get hasAccessToken => _accessToken != null;

  void setAccessToken(String accessToken) {
    _accessToken = accessToken;
  }

  Future<String?> readRefreshToken() => _refreshTokenStorage.read();

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    await _refreshTokenStorage.write(refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    await _refreshTokenStorage.delete();
  }
}
