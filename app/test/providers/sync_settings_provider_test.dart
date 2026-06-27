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
      powerSyncServiceUri: Uri.parse('https://data-sync.papyrus.test'),
    );
  }

  SyncSettingsProvider providerWithFetcher(
    SharedPreferences prefs, {
    Map<String, DataSyncDiscoverySettings>? discovered,
  }) {
    return SyncSettingsProvider(
      prefs,
      officialConfig: officialConfig(),
      discoveryFetcher: (serverUrl) async {
        final settings = discovered?[serverUrl.toString()];
        if (settings == null) {
          throw SyncSettingsException('Server settings could not be loaded');
        }
        return settings;
      },
    );
  }

  test('defaults to the official data sync profile with 1 GB file storage', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    expect(provider.activeServerId, SyncSettingsProvider.officialServerId);
    expect(provider.activeServerLabel, 'Official server');
    expect(provider.activeProfileKey, 'official');
    expect(provider.activeApiConfig.serverBaseUri, Uri.parse('https://api.papyrus.test'));
    expect(provider.activeApiConfig.powerSyncServiceUri, Uri.parse('https://data-sync.papyrus.test'));
    expect(provider.fileStorageLabel, 'Up to 1 GB included');
    expect(provider.customServers, isEmpty);
  });

  test('adds multiple custom servers from one public URL and switches the active server', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = providerWithFetcher(
      prefs,
      discovered: {
        'http://localhost:8080': DataSyncDiscoverySettings(
          dataSyncUri: Uri.parse('http://localhost:8081'),
          fileStorageQuotaBytes: 1_073_741_824,
        ),
        'https://reader.example': DataSyncDiscoverySettings(
          dataSyncUri: Uri.parse('https://sync.reader.example'),
          fileStorageQuotaBytes: 2_147_483_648,
        ),
      },
    );

    final local = await provider.addCustomServer('localhost:8080');
    final remote = await provider.addCustomServer('https://reader.example');
    provider.selectServer(local.id);

    final restored = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    expect(restored.customServers.map((server) => server.url), ['http://localhost:8080', 'https://reader.example']);
    expect(restored.activeServerId, local.id);
    expect(restored.activeServerLabel, 'localhost:8080');
    expect(restored.activeApiConfig.serverBaseUri, Uri.parse('http://localhost:8080'));
    expect(restored.activeApiConfig.powerSyncServiceUri, Uri.parse('http://localhost:8081'));
    expect(restored.activeProfileKey, startsWith('custom-'));
    expect(remote.id, isNot(local.id));
  });

  test('rejects duplicate custom server URLs after normalization', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = providerWithFetcher(
      prefs,
      discovered: {
        'http://localhost:8080': DataSyncDiscoverySettings(
          dataSyncUri: Uri.parse('http://localhost:8081'),
          fileStorageQuotaBytes: null,
        ),
      },
    );

    await provider.addCustomServer('localhost:8080');

    await expectLater(
      provider.addCustomServer('http://localhost:8080/'),
      throwsA(isA<SyncSettingsException>().having((error) => error.message, 'message', contains('already exists'))),
    );
  });

  test('removing the active custom server switches back to official', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = providerWithFetcher(
      prefs,
      discovered: {
        'http://localhost:8080': DataSyncDiscoverySettings(
          dataSyncUri: Uri.parse('http://localhost:8081'),
          fileStorageQuotaBytes: null,
        ),
      },
    );

    final custom = await provider.addCustomServer('localhost:8080');

    provider.removeCustomServer(custom.id);

    expect(provider.activeServerId, SyncSettingsProvider.officialServerId);
    expect(provider.customServers, isEmpty);
  });

  test('migrates legacy single custom API and sync URLs', () async {
    SharedPreferences.setMockInitialValues({
      'sync_server_type': 'custom',
      'sync_custom_api_url': 'http://legacy-api.test',
      'sync_custom_powersync_url': 'http://legacy-sync.test',
    });
    final prefs = await SharedPreferences.getInstance();

    final provider = SyncSettingsProvider(prefs, officialConfig: officialConfig());

    expect(provider.customServers, hasLength(1));
    expect(provider.activeServerId, provider.customServers.single.id);
    expect(provider.activeServerLabel, 'legacy-api.test');
    expect(provider.activeApiConfig.serverBaseUri, Uri.parse('http://legacy-api.test'));
    expect(provider.activeApiConfig.powerSyncServiceUri, Uri.parse('http://legacy-sync.test'));
  });
}
