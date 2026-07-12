import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/storage_sync_controller.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRefreshTokenStorage implements RefreshTokenStorage {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String refreshToken) async {}
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'))),
        tokenStore: TokenStore(_MemoryRefreshTokenStorage()),
      );

  @override
  Future<AuthTokens?> bootstrap() async => AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: '11111111-1111-1111-1111-111111111111',
      email: 'reader@example.com',
      displayName: 'Reader',
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
    ),
  );
}

class _OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

class _FakePowerSyncService extends PapyrusPowerSyncService {
  _FakePowerSyncService() : super(connectorFactory: _OfflineConnector.new, connectAuthenticated: false);

  @override
  LibraryDatabaseMode? get mode => LibraryDatabaseMode.authenticated;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('failed media upload label is exposed for authenticated storage sync UI', () async {
    final prefs = await SharedPreferences.getInstance();
    final authProvider = AuthProvider(prefs, repository: _FakeAuthRepository(), bootstrapOnCreate: false);
    await authProvider.bootstrap();
    final controller = StorageSyncController(
      authProvider: authProvider,
      powerSyncService: _FakePowerSyncService(),
      syncSettings: SyncSettingsProvider(
        prefs,
        officialConfig: PapyrusApiConfig(
          serverBaseUri: Uri.parse('https://api.test'),
          powerSyncServiceUri: Uri.parse('https://sync.test'),
        ),
      ),
      syncState: const SyncState(connected: true),
      fileStorageUsedBytes: 0,
      failedMediaUploadCount: 2,
    );

    expect(controller.hasFailedMediaUploads, isTrue);
    expect(controller.failedMediaUploadLabel, '2 failed');
  });
}
