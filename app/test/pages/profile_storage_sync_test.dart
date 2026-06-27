import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/profile_page.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRefreshTokenStorage implements RefreshTokenStorage {
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

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'))),
        tokenStore: TokenStore(_MemoryRefreshTokenStorage()),
      );

  AuthTokens? bootstrapResult;

  @override
  Future<AuthTokens?> bootstrap() async {
    return bootstrapResult;
  }

  @override
  Future<void> clearTokens() async {}
}

class _OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

class _FakePowerSyncService extends PapyrusPowerSyncService {
  _FakePowerSyncService({required this.currentMode, required this.currentSyncState})
    : super(connectorFactory: _OfflineConnector.new, connectAuthenticated: false);

  LibraryDatabaseMode? currentMode;
  SyncState currentSyncState;
  int reconnectCalls = 0;
  int clearGuestLibraryCalls = 0;
  int clearAuthenticatedCacheCalls = 0;

  @override
  LibraryDatabaseMode? get mode => currentMode;

  @override
  SyncState get syncState => currentSyncState;

  @override
  Stream<SyncState> get syncStates => Stream.value(currentSyncState);

  @override
  Future<void> reconnect() async {
    reconnectCalls += 1;
  }

  @override
  Future<void> clearGuestLibrary() async {
    clearGuestLibraryCalls += 1;
  }

  @override
  Future<void> clearAuthenticatedCache() async {
    clearAuthenticatedCacheCalls += 1;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AuthProvider> buildAuthProvider({bool guest = false, bool signedIn = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = _FakeAuthRepository();
    if (signedIn) {
      repository.bootstrapResult = _tokens();
    }
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);
    await provider.bootstrap();
    if (guest) {
      provider.setOfflineMode(true);
    }
    return provider;
  }

  Future<Widget> buildPage({
    required AuthProvider authProvider,
    required _FakePowerSyncService powerSyncService,
    Size screenSize = const Size(400, 900),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final config = PapyrusApiConfig(
      serverBaseUri: Uri.parse('https://api.test'),
      powerSyncServiceUri: Uri.parse('https://powersync.test'),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncSettingsProvider>(
          create: (_) => SyncSettingsProvider(prefs, officialConfig: config),
        ),
        Provider<PapyrusPowerSyncService>.value(value: powerSyncService),
        StreamProvider<SyncState>.value(value: powerSyncService.syncStates, initialData: powerSyncService.syncState),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<PreferencesProvider>(create: (_) => PreferencesProvider(prefs)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: const ProfilePage(),
        ),
      ),
    );
  }

  testWidgets('offline storage sync UI is local-first and hides sync internals', (tester) async {
    final auth = await buildAuthProvider(guest: true);
    final service = _FakePowerSyncService(currentMode: LibraryDatabaseMode.guest, currentSyncState: const SyncState());

    await tester.pumpWidget(await buildPage(authProvider: auth, powerSyncService: service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Storage & sync'), 400);
    await tester.pumpAndSettle();

    expect(find.text('Stored on this device'), findsOneWidget);
    expect(find.text('Export or import a backup'), findsOneWidget);
    expect(find.text('Clear local library'), findsOneWidget);
    expect(find.textContaining('Nothing is sent to Papyrus servers'), findsOneWidget);
    expect(find.text('Guest local'), findsNothing);
    expect(find.text('papyrus-guest.db'), findsNothing);
    expect(find.text('Metadata sync off'), findsNothing);
    expect(find.text('Clear guest library'), findsNothing);
    expect(find.text('https://api.test'), findsNothing);
    expect(find.text('https://powersync.test'), findsNothing);
    expect(find.text('Current mode'), findsNothing);
    expect(find.text('Local database'), findsNothing);
    expect(find.text('Metadata sync'), findsNothing);
    expect(find.text('Media storage'), findsNothing);
    expect(find.text('Storage backend'), findsNothing);
    expect(find.text('Sync enabled'), findsNothing);
    expect(find.text('Sync interval'), findsNothing);
    expect(find.text('Conflict resolution'), findsNothing);
    expect(find.text('Add storage backend'), findsNothing);
  });

  testWidgets('offline desktop storage sync is local-first and hides sync internals', (tester) async {
    final auth = await buildAuthProvider(guest: true);
    final service = _FakePowerSyncService(currentMode: LibraryDatabaseMode.guest, currentSyncState: const SyncState());

    await tester.pumpWidget(
      await buildPage(authProvider: auth, powerSyncService: service, screenSize: const Size(1200, 900)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage & sync').first);
    await tester.pumpAndSettle();

    expect(find.text('Library storage'), findsOneWidget);
    expect(find.text('Your library is stored on this device.'), findsOneWidget);
    expect(find.textContaining('Nothing is sent to Papyrus servers'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Clear local library'), findsOneWidget);
    expect(find.text('Guest local'), findsNothing);
    expect(find.text('papyrus-guest.db'), findsNothing);
    expect(find.text('Metadata sync off'), findsNothing);
    expect(find.text('Clear guest library'), findsNothing);
    expect(find.text('Current mode'), findsNothing);
    expect(find.text('Local database'), findsNothing);
    expect(find.text('Metadata sync'), findsNothing);
    expect(find.text('Media storage'), findsNothing);
  });

  testWidgets('authenticated storage sync UI shows official metadata sync and local-only media policy', (tester) async {
    final auth = await buildAuthProvider(signedIn: true);
    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: SyncState(connected: true, lastSyncedAt: DateTime.utc(2026, 6, 27, 10, 30)),
    );

    await tester.pumpWidget(await buildPage(authProvider: auth, powerSyncService: service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Storage & sync'), 400);
    await tester.pumpAndSettle();

    expect(find.text('Account synced'), findsWidgets);
    expect(find.text('Server-scoped account cache'), findsOneWidget);
    expect(find.text('Official server'), findsWidgets);
    expect(find.text('Local device only'), findsOneWidget);
    expect(find.textContaining('Official servers do not store book files or covers'), findsOneWidget);
    expect(find.text('Connected'), findsWidgets);
    expect(find.text('Reconnect sync'), findsOneWidget);
    expect(find.text('Clear account local cache'), findsOneWidget);

    await tester.ensureVisible(find.text('Reconnect sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect sync'));
    await tester.pump();

    expect(service.reconnectCalls, 1);
  });

  testWidgets('storage sync UI shows pending writes and sync errors', (tester) async {
    final auth = await buildAuthProvider(signedIn: true);
    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: const SyncState(connected: true, hasPendingWrites: true, uploadError: 'upload failed'),
    );

    await tester.pumpWidget(await buildPage(authProvider: auth, powerSyncService: service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Storage & sync'), 400);
    await tester.pumpAndSettle();

    expect(find.text('Error'), findsWidgets);
    expect(find.text('Sync error: upload failed'), findsOneWidget);
    expect(find.text('Local changes pending upload'), findsOneWidget);
  });
}

AuthTokens _tokens() {
  return AuthTokens(
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
