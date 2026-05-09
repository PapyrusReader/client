import 'package:flutter_test/flutter_test.dart';
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
  test('TokenStore saves, rotates, and clears tokens', () async {
    final storage = MemoryRefreshTokenStorage();
    final store = TokenStore(storage);

    await store.saveTokens(accessToken: 'access-one', refreshToken: 'refresh-one');
    expect(store.accessToken, 'access-one');
    expect(await store.readRefreshToken(), 'refresh-one');

    await store.saveTokens(accessToken: 'access-two', refreshToken: 'refresh-two');
    expect(store.accessToken, 'access-two');
    expect(await store.readRefreshToken(), 'refresh-two');

    await store.clear();
    expect(store.accessToken, isNull);
    expect(await store.readRefreshToken(), isNull);
  });
}
