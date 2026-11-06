import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/widgets/profile/storage_sync_settings_section.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/profile_page.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/acquisition_availability_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:powersync/powersync.dart' hide Column;
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
  List<Book> guestBooks = [];

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
  Future<void> clearGuestLibrary({required Future<void> Function(List<Book>) deleteFiles}) async {
    await deleteFiles(guestBooks);
    guestBooks = [];
    clearGuestLibraryCalls += 1;
  }

  @override
  Future<void> clearAuthenticatedCache() async {
    clearAuthenticatedCacheCalls += 1;
  }
}

class _Files extends BookImportService {
  final deletedBooks = <String>[];
  final clearedScopes = <MediaStorageScope>[];
  bool failDeletion = false;

  @override
  Future<void> deleteBookFile(String bookId) async {
    if (failDeletion) {
      throw StateError('Storage unavailable');
    }

    deletedBooks.add(bookId);
  }

  @override
  Future<void> clearCoverFiles(MediaStorageScope scope) async {
    clearedScopes.add(scope);
  }
}

class _Folders extends ChangeNotifier implements WatchedFolders {
  bool suspended = false;
  int clearCalls = 0;

  @override
  Future<void> suspend() async {
    suspended = true;
  }

  @override
  void resume() {
    suspended = false;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    SyncSettingsProvider? syncSettingsProvider,
    DataStore? dataStore,
    MediaUploadQueue? mediaUploadQueue,
    AcquisitionAvailabilityProvider? acquisitionAvailabilityProvider,
    Widget Function(Widget page)? pageBuilder,
    BookImportService? files,
    WatchedFolders? folders,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final config = PapyrusApiConfig(
      serverBaseUri: Uri.parse('https://api.test'),
      powerSyncServiceUri: Uri.parse('https://data-sync.test'),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DataStore>.value(value: dataStore ?? DataStore()),
        ChangeNotifierProvider<MediaUploadQueue>.value(value: mediaUploadQueue ?? MediaUploadQueue(prefs)),
        ChangeNotifierProvider<SyncSettingsProvider>.value(
          value: syncSettingsProvider ?? SyncSettingsProvider(prefs, officialConfig: config),
        ),
        Provider<PapyrusPowerSyncService>.value(value: powerSyncService),
        if (files != null) Provider<BookImportService>.value(value: files),
        if (folders != null) ChangeNotifierProvider<WatchedFolders>.value(value: folders),
        StreamProvider<SyncState>.value(value: powerSyncService.syncStates, initialData: powerSyncService.syncState),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AcquisitionAvailabilityProvider>.value(
          value:
              acquisitionAvailabilityProvider ??
              AcquisitionAvailabilityProvider(
                loadCapabilities: (_) async => const AcquisitionCapabilities(
                  enabled: false,
                  endpointKinds: [],
                  indexerKinds: [],
                  downloadClientKinds: [],
                  arrKinds: [],
                  arrCommands: {},
                ),
              ),
        ),
        ChangeNotifierProvider<PreferencesProvider>(create: (_) => PreferencesProvider(prefs)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: pageBuilder?.call(const ProfilePage()) ?? const ProfilePage(section: ProfileSection.storageSync),
        ),
      ),
    );
  }

  testWidgets('clearing the guest library removes its files and covers before discarding records', (tester) async {
    final auth = await buildAuthProvider(guest: true);
    final service = _FakePowerSyncService(currentMode: LibraryDatabaseMode.guest, currentSyncState: const SyncState());
    final files = _Files()..failDeletion = true;
    final folders = _Folders();
    addTearDown(folders.dispose);
    service.guestBooks = [Book(id: 'guest-book', title: 'Guest book', author: 'Reader', addedAt: DateTime.now())];

    await tester.pumpWidget(
      await buildPage(
        authProvider: auth,
        powerSyncService: service,
        files: files,
        folders: folders,
        pageBuilder: (_) => const Scaffold(body: StorageSyncSettingsSection()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear local library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not clear local library'), findsOneWidget);
    expect(service.guestBooks.single.id, 'guest-book');
    expect(service.clearGuestLibraryCalls, 0);
    expect(folders.suspended, isFalse);
    expect(folders.clearCalls, 0);
    files.failDeletion = false;
    await tester.tap(find.text('Clear local library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear library'));
    await tester.pumpAndSettle();
    expect(files.deletedBooks, ['guest-book']);
    expect(files.clearedScopes, [MediaStorageScope.localGuest]);
    expect(service.guestBooks, isEmpty);
    expect(service.clearGuestLibraryCalls, 1);
    expect(folders.suspended, isFalse);
    expect(folders.clearCalls, 1);
    expect(auth.isOfflineMode, isTrue);
  });

  testWidgets('offline storage sync UI is local-first and hides sync internals', (tester) async {
    final auth = await buildAuthProvider(guest: true);
    final service = _FakePowerSyncService(currentMode: LibraryDatabaseMode.guest, currentSyncState: const SyncState());
    await tester.pumpWidget(await buildPage(authProvider: auth, powerSyncService: service));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Stored on this device'), findsOneWidget);
    expect(find.text('Export or import a backup'), findsOneWidget);
    expect(find.text('Clear local library'), findsOneWidget);
    expect(find.textContaining('Nothing is sent to Papyrus servers'), findsNothing);
    expect(find.text('Guest local'), findsNothing);
    expect(find.text('papyrus-guest.db'), findsNothing);
    expect(find.text('Metadata sync off'), findsNothing);
    expect(find.text('Clear guest library'), findsNothing);
    expect(find.text('https://api.test'), findsNothing);
    expect(find.text('https://data-sync.test'), findsNothing);
    expect(find.text('Current mode'), findsNothing);
    expect(find.text('Local database'), findsNothing);
    expect(find.text('Metadata sync'), findsNothing);
    expect(find.text('Media storage'), findsNothing);
    expect(find.text('Storage backend'), findsNothing);
    expect(find.text('Sync enabled'), findsNothing);
    expect(find.text('Sync interval'), findsNothing);
    expect(find.text('Conflict resolution'), findsNothing);
    expect(find.text('Add storage backend'), findsNothing);
    expect(find.text('Pending changes'), findsNothing);
    expect(find.text('No pending local writes'), findsNothing);
    expect(find.byKey(const Key('profile-acquisition-section')), findsNothing);
    expect(find.text('Enable acquisition'), findsNothing);
  });

  testWidgets('authenticated mobile storage omits acquisition settings', (tester) async {
    final auth = await buildAuthProvider(signedIn: true);
    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: const SyncState(connected: true),
    );
    final availability = AcquisitionAvailabilityProvider(loadCapabilities: (_) async => _capabilities(enabled: true));
    await availability.refresh(Uri.parse('https://api.test'));

    await tester.pumpWidget(
      await buildPage(authProvider: auth, powerSyncService: service, acquisitionAvailabilityProvider: availability),
    );

    await tester.pumpAndSettle();
    expect(find.text('File storage'), findsOneWidget);
    expect(find.text('Acquisition'), findsNothing);
    expect(find.text('Enable acquisition'), findsNothing);
    expect(find.text('Manage integrations'), findsNothing);
  });

  testWidgets('offline desktop storage sync is local-first and hides sync internals', (tester) async {
    final auth = await buildAuthProvider(guest: true);
    final service = _FakePowerSyncService(currentMode: LibraryDatabaseMode.guest, currentSyncState: const SyncState());

    await tester.pumpWidget(
      await buildPage(authProvider: auth, powerSyncService: service, screenSize: const Size(1200, 900)),
    );

    await tester.pump();
    await tester.tap(find.text('Storage').first);
    await tester.pump();
    expect(find.text('Library storage'), findsOneWidget);
    expect(find.text('Your library is stored on this device.'), findsOneWidget);
    expect(find.textContaining('Nothing is sent to Papyrus servers'), findsNothing);
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
    expect(find.text('Pending changes'), findsNothing);
    expect(find.text('No pending local writes'), findsNothing);
    expect(find.byKey(const Key('profile-acquisition-card')), findsNothing);
    expect(find.text('Enable acquisition'), findsNothing);
  });

  testWidgets('authenticated storage sync UI shows data sync and hides implementation details', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = await buildAuthProvider(signedIn: true);

    final dataStore = dataStoreWithBooks([
      testBook(id: 'book-1', title: 'Small book', fileSize: 100 * 1024 * 1024),
      testBook(id: 'book-2', title: 'Large book', fileSize: 250 * 1024 * 1024),
    ]);

    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: SyncState(connected: true, lastSyncedAt: DateTime.utc(2026, 6, 27, 10, 30)),
    );

    final availability = AcquisitionAvailabilityProvider(loadCapabilities: (_) async => _capabilities(enabled: true));
    await availability.refresh(Uri.parse('https://api.test'));

    await tester.pumpWidget(
      await buildPage(
        authProvider: auth,
        powerSyncService: service,
        screenSize: const Size(1200, 900),
        dataStore: dataStore,
        acquisitionAvailabilityProvider: availability,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage').first);
    await tester.pumpAndSettle();
    expect(find.text('Data sync'), findsOneWidget);
    expect(find.text('Official server'), findsWidgets);
    expect(find.text('350 MB used, 674 MB available of 1 GB'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 350 / 1024);
    final reconnectButton = find.widgetWithText(OutlinedButton, 'Reconnect');
    final manageButton = find.widgetWithText(OutlinedButton, 'Manage servers');
    expect(
      tester.getSize(reconnectButton).width,
      lessThan(tester.getSize(find.byKey(const Key('profile-data-sync-card'))).width / 2),
    );
    expect(tester.getTopLeft(reconnectButton).dy, tester.getTopLeft(manageButton).dy);
    expect(find.text('Connected'), findsWidgets);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Manage servers'), findsOneWidget);
    expect(find.byKey(const Key('profile-data-sync-card')), findsOneWidget);
    expect(find.byKey(const Key('profile-acquisition-card')), findsNothing);
    expect(find.text('Acquisition'), findsNothing);
    expect(find.text('Enable acquisition'), findsNothing);
    expect(find.text('Available on this server'), findsNothing);
    expect(find.text('Search external sources and send releases to your connected clients.'), findsNothing);
    expect(find.text('Manage integrations'), findsNothing);
    expect(find.text('Clear local copy'), findsOneWidget);
    expect(find.text('Clear account local cache'), findsNothing);
    expect(find.text('Pending changes'), findsNothing);
    expect(find.text('Metadata sync'), findsNothing);
    expect(find.text('PowerSync service'), findsNothing);
    expect(find.textContaining('PowerSync'), findsNothing);
    expect(find.text('Library storage'), findsNothing);
    expect(find.text('Media storage'), findsNothing);
    expect(find.text('Local database'), findsNothing);
    expect(find.text('Server-scoped account cache'), findsNothing);
    await tester.ensureVisible(find.text('Reconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(service.reconnectCalls, 1);
  });

  testWidgets('manage servers lists official and custom servers for switching', (tester) async {
    final prefs = await SharedPreferences.getInstance();

    final syncSettings = SyncSettingsProvider(
      prefs,
      officialConfig: PapyrusApiConfig(
        serverBaseUri: Uri.parse('https://api.test'),
        powerSyncServiceUri: Uri.parse('https://data-sync.test'),
      ),
      discoveryFetcher: (serverUrl) async => DataSyncDiscoverySettings(
        dataSyncUri: Uri.parse('https://sync.${serverUrl.host}'),
        fileStorageQuotaBytes: 1_073_741_824,
      ),
    );

    await syncSettings.addCustomServer('https://reader.example');
    syncSettings.selectServer(SyncSettingsProvider.officialServerId);
    final auth = await buildAuthProvider(signedIn: true);

    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: const SyncState(connected: true),
    );

    await tester.pumpWidget(
      await buildPage(authProvider: auth, powerSyncService: service, syncSettingsProvider: syncSettings),
    );

    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage servers'));
    await tester.pumpAndSettle();
    expect(find.text('Sync servers'), findsOneWidget);
    expect(find.text('Official server'), findsWidgets);
    expect(find.text('reader.example'), findsOneWidget);
    expect(find.text('Add custom server'), findsOneWidget);
  });

  testWidgets('manage servers blocks the sidebar outside the settings navigator', (tester) async {
    const size = Size(1440, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = await buildAuthProvider(signedIn: true);
    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: const SyncState(connected: true),
    );
    var sidebarActivations = 0;

    await tester.pumpWidget(
      await buildPage(
        authProvider: auth,
        powerSyncService: service,
        screenSize: size,
        pageBuilder: (page) => Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 240,
                child: TextButton(
                  onPressed: () => sidebarActivations++,
                  child: const Text('Main sidebar'),
                ),
              ),
              Expanded(
                child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page)),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'Storage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage servers'));
    await tester.pumpAndSettle();
    final barrier = find.byType(ModalBarrier).last;
    expect(tester.getRect(barrier), Offset.zero & size);
    await tester.tapAt(tester.getCenter(find.text('Main sidebar')));
    await tester.pumpAndSettle();
    expect(sidebarActivations, 0);
    expect(find.text('Sync servers'), findsNothing);
    await tester.tap(find.text('Manage servers'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Official server'));
    await tester.pumpAndSettle();
    expect(find.text('Sync servers'), findsNothing);
    expect(find.text('Manage servers'), findsOneWidget);
  });

  testWidgets('storage sync UI shows pending writes and sync errors', (tester) async {
    final auth = await buildAuthProvider(signedIn: true);

    final service = _FakePowerSyncService(
      currentMode: LibraryDatabaseMode.authenticated,
      currentSyncState: const SyncState(connected: true, hasPendingWrites: true, uploadError: 'upload failed'),
    );

    await tester.pumpWidget(
      await buildPage(authProvider: auth, powerSyncService: service, screenSize: const Size(1200, 900)),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage').first);
    await tester.pumpAndSettle();
    expect(find.text('Error'), findsWidgets);
    expect(find.text('Sync error: upload failed'), findsOneWidget);
    expect(find.text('Pending changes'), findsNothing);
    expect(find.text('Local changes pending upload'), findsNothing);
  });
}

DataStore dataStoreWithBooks(List<Book> books) {
  final repository = InMemoryBookRepository()..replaceAll(books);
  return DataStore(bookRepository: repository);
}

Book testBook({required String id, required String title, int? fileSize}) {
  return Book(id: id, title: title, author: 'Author', fileSize: fileSize, addedAt: DateTime.utc(2026, 6, 27));
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

AcquisitionCapabilities _capabilities({required bool enabled}) {
  return AcquisitionCapabilities(
    enabled: enabled,
    endpointKinds: const [],
    indexerKinds: const [],
    downloadClientKinds: const [],
    arrKinds: const [],
    arrCommands: const {},
  );
}
