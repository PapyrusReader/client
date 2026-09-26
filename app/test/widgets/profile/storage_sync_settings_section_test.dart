import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/acquisition_availability_provider.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/widgets/profile/storage_sync_settings_section.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements RefreshTokenStorage {
  String? token;
  @override
  Future<void> delete() async => token = null;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String val) async => token = val;
}

class _MockAuthRepo extends AuthRepository {
  _MockAuthRepo()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'))),
        tokenStore: TokenStore(_MemoryStorage()),
      );

  @override
  Future<AuthTokens?> bootstrap() async => null;
}

class _OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

class _MockPowerSyncService extends PapyrusPowerSyncService {
  _MockPowerSyncService() : super(connectorFactory: _OfflineConnector.new, connectAuthenticated: false);

  @override
  LibraryDatabaseMode? get mode => LibraryDatabaseMode.guest;

  @override
  SyncState get syncState => const SyncState(connected: true, connecting: false, downloading: false, uploading: false);

  @override
  Stream<SyncState> get syncStates => Stream.value(syncState);
}

void main() {
  group('StorageSyncSettingsSection', () {
    late SharedPreferences prefs;
    late AuthProvider authProvider;
    late _MockPowerSyncService powerSync;
    late SyncSettingsProvider syncSettings;
    late DataStore dataStore;
    late MediaUploadQueue uploadQueue;
    late PreferencesProvider prefsProvider;
    late AcquisitionAvailabilityProvider availabilityProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      authProvider = AuthProvider(prefs, repository: _MockAuthRepo(), bootstrapOnCreate: false);
      await authProvider.bootstrap();
      authProvider.setOfflineMode(true);
      powerSync = _MockPowerSyncService();
      syncSettings = SyncSettingsProvider(
        prefs,
        officialConfig: PapyrusApiConfig(
          serverBaseUri: Uri.parse('https://api.test'),
          powerSyncServiceUri: Uri.parse('https://data-sync.test'),
        ),
      );
      dataStore = DataStore();
      uploadQueue = MediaUploadQueue(prefs);
      prefsProvider = PreferencesProvider(prefs);
      availabilityProvider = AcquisitionAvailabilityProvider(authProvider: authProvider);
    });

    Widget buildSection({bool isDesktop = false}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          Provider<PapyrusPowerSyncService>.value(value: powerSync),
          ChangeNotifierProvider<SyncSettingsProvider>.value(value: syncSettings),
          StreamProvider<SyncState>.value(value: powerSync.syncStates, initialData: powerSync.syncState),
          ChangeNotifierProvider<DataStore>.value(value: dataStore),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: uploadQueue),
          ChangeNotifierProvider<PreferencesProvider>.value(value: prefsProvider),
          ChangeNotifierProvider<AcquisitionAvailabilityProvider>.value(value: availabilityProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StorageSyncSettingsSection(isDesktop: isDesktop)),
          ),
        ),
      );
    }

    testWidgets('renders desktop offline storage card and actions', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: true));

      expect(find.text('Library storage'), findsOneWidget);
      expect(find.text('Your library is stored on this device.'), findsOneWidget);
      expect(find.text('Export backup'), findsOneWidget);
      expect(find.text('Import backup'), findsOneWidget);
      expect(find.text('Clear local library'), findsOneWidget);
    });

    testWidgets('renders mobile storage settings rows', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: false));

      expect(find.text('Storage'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Stored on this device'), findsOneWidget);
      expect(find.text('Export or import a backup'), findsOneWidget);
      expect(find.text('Clear local library'), findsOneWidget);
    });
  });
}
