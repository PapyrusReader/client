import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

const runIntegration = bool.fromEnvironment('RUN_POWERSYNC_INTEGRATION');

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String refreshToken) async => value = refreshToken;
}

Future<void> waitForBook(PapyrusPowerSyncService service, String id, {bool present = true, String? title}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final book = await service.getById(id);
    if ((book != null) == present && (title == null || book?.title == title)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Book $id did not reach expected presence=$present');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two clients sync books, reconnect offline writes, and isolate users', (tester) async {
    final config = PapyrusApiConfig.fromEnvironment();
    final email = 'powersync-${DateTime.now().microsecondsSinceEpoch}@example.com';
    const password = 'SecureP@ss123';
    final root = await Directory.systemTemp.createTemp('papyrus-e2e-');

    AuthRepository repository(String label) {
      return AuthRepository(
        apiClient: AuthApiClient(config: config),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );
    }

    PapyrusPowerSyncService service(AuthRepository repository, String label) {
      return PapyrusPowerSyncService(
        connectorFactory: () => PapyrusPowerSyncConnector(authRepository: repository, config: config),
        pathResolver: (mode, profileKey, userId) async =>
            path.join(root.path, '$label-${mode.name}-${profileKey ?? 'default'}-${userId ?? 'none'}.db'),
      );
    }

    final firstAuth = repository('first');
    final firstTokens = await firstAuth.register(
      email: email,
      password: password,
      displayName: 'PowerSync Test',
      clientType: 'desktop',
    );
    final secondAuth = repository('second');
    await secondAuth.login(email: email, password: password, clientType: 'desktop');
    final otherAuth = repository('other');
    final otherTokens = await otherAuth.register(
      email: 'other-$email',
      password: password,
      displayName: 'Other User',
      clientType: 'desktop',
    );

    final first = service(firstAuth, 'first');
    final second = service(secondAuth, 'second');
    final other = service(otherAuth, 'other');

    try {
      await Future.wait([
        first.activateAuthenticated(firstTokens.user.userId),
        second.activateAuthenticated(firstTokens.user.userId),
        other.activateAuthenticated(otherTokens.user.userId),
      ]);
      await Future.wait([
        first.syncStates.firstWhere((state) => state.connected),
        second.syncStates.firstWhere((state) => state.connected),
        other.syncStates.firstWhere((state) => state.connected),
      ]).timeout(const Duration(seconds: 20));

      final book = Book(
        id: const Uuid().v4(),
        title: 'Realtime book',
        author: 'Papyrus',
        addedAt: DateTime.now().toUtc(),
      );
      await first.upsert(book);
      await waitForBook(second, book.id, title: book.title);
      expect(await other.getById(book.id), isNull);

      await first.setOnline(false);
      await first.upsert(book.copyWith(title: 'Offline edit'));
      await first.setOnline(true);
      await waitForBook(second, book.id, title: 'Offline edit');
      expect((await second.getById(book.id))?.title, 'Offline edit');

      await second.delete(book.id);
      await waitForBook(first, book.id, present: false);
    } finally {
      await Future.wait([first.close(), second.close(), other.close()]);
      await root.delete(recursive: true);
    }
  }, skip: !runIntegration);
}
