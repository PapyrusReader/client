import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PapyrusApiConfig officialConfig() {
    return PapyrusApiConfig(
      serverBaseUri: Uri.parse('https://api.papyrus.test'),
      powerSyncServiceUri: Uri.parse('https://powersync.papyrus.test'),
    );
  }

  test('defaults to the official metadata sync profile and local-only media storage', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    expect(provider.serverType, SyncServerType.official);
    expect(provider.activeServerLabel, 'Official server');
    expect(provider.activeProfileKey, 'official');
    expect(provider.activeApiConfig.serverBaseUri, Uri.parse('https://api.papyrus.test'));
    expect(provider.activeApiConfig.powerSyncServiceUri, Uri.parse('https://powersync.papyrus.test'));
    expect(provider.mediaStorageBackend, MediaStorageBackend.local);
  });

  test('persists a custom metadata sync profile with a stable profile key', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    provider.setCustomServerUrls(apiUrl: 'http://localhost:8080', powerSyncUrl: 'http://localhost:8081');
    provider.serverType = SyncServerType.custom;

    final restored = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    expect(restored.serverType, SyncServerType.custom);
    expect(restored.activeServerLabel, 'Custom server');
    expect(restored.customApiUrl, 'http://localhost:8080');
    expect(restored.customPowerSyncUrl, 'http://localhost:8081');
    expect(restored.activeApiConfig.serverBaseUri, Uri.parse('http://localhost:8080'));
    expect(restored.activeApiConfig.powerSyncServiceUri, Uri.parse('http://localhost:8081'));
    expect(restored.activeProfileKey, provider.activeProfileKey);
    expect(restored.activeProfileKey, startsWith('custom-'));
  });

  test('does not allow official servers to be selected for media file storage', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    provider.mediaStorageBackend = MediaStorageBackend.selfHosted;

    expect(provider.serverType, SyncServerType.official);
    expect(provider.mediaStorageBackend, MediaStorageBackend.local);
    expect(provider.mediaStorageRestrictionMessage, contains('Official servers do not store book files or covers'));
  });

  test('allows self-hosted media storage only when a custom sync server is active', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    provider.setCustomServerUrls(apiUrl: 'http://localhost:8080', powerSyncUrl: 'http://localhost:8081');
    provider.serverType = SyncServerType.custom;
    provider.mediaStorageBackend = MediaStorageBackend.selfHosted;

    expect(provider.mediaStorageBackend, MediaStorageBackend.selfHosted);

    provider.serverType = SyncServerType.official;

    expect(provider.mediaStorageBackend, MediaStorageBackend.local);
  });
}
