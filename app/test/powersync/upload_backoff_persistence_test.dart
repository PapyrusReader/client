import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:powersync/powersync.dart';

import '../auth/auth_repository_powersync_test.dart' show MemoryRefreshTokenStorage;

void main() {
  test('rate limiting preserves queued mutations until a later successful upload', () async {
    final directory = await Directory.systemTemp.createTemp('papyrus-upload-backoff-');
    final database = PowerSyncDatabase(path: '${directory.path}/library.db', schema: papyrusAccountSchema);
    await database.initialize();

    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await database.execute("INSERT INTO books (id, title) VALUES ('book-id', 'Offline book')");
    final queuedBefore = await database.getAll('SELECT * FROM ps_crud');
    expect(queuedBefore, isNotEmpty);
    final store = TokenStore(MemoryRefreshTokenStorage());
    await store.saveTokens(accessToken: 'access-token', refreshToken: 'refresh-token');
    var now = DateTime.utc(2026, 10, 22);
    var requests = 0;
    final config = PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test'));

    final api = AuthApiClient(
      config: config,
      now: () => now,
      httpClient: MockClient((request) async {
        requests++;

        if (requests == 1) {
          return http.Response('{}', 429, headers: {'retry-after': '30'});
        }

        return http.Response('{"applied_count":1}', 200);
      }),
    );

    final connector = PapyrusPowerSyncConnector(
      config: config,
      authRepository: AuthRepository(apiClient: api, tokenStore: store),
    );

    await expectLater(connector.uploadData(database), throwsA(isA<AuthApiException>()));
    expect(await database.getAll('SELECT * FROM ps_crud'), queuedBefore);
    await expectLater(connector.uploadData(database), throwsA(isA<AuthApiException>()));
    expect(requests, 1);
    expect(await database.getAll('SELECT * FROM ps_crud'), queuedBefore);
    now = now.add(const Duration(seconds: 30));
    await connector.uploadData(database);
    expect(requests, 2);
    expect(await database.getAll('SELECT * FROM ps_crud'), isEmpty);
    expect((await database.get('SELECT title FROM books WHERE id = ?', ['book-id']))['title'], 'Offline book');
  });
}
