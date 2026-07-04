import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/services/book_download_service.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_router.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();
  runApp(Papyrus(prefs: prefs));
}

class Papyrus extends StatefulWidget {
  final SharedPreferences prefs;

  const Papyrus({super.key, required this.prefs});

  @override
  State<Papyrus> createState() => _PapyrusState();
}

class _PapyrusState extends State<Papyrus> {
  late final DataStore _dataStore;
  late final AuthProvider _authProvider;
  late final SyncSettingsProvider _syncSettingsProvider;
  late final MediaUploadQueue _mediaUploadQueue;
  late final BookImportService _bookImportService;
  late final PapyrusPowerSyncService _powerSyncService;
  late final PapyrusApiConfig _officialApiConfig;
  late AuthRepository _authRepository;
  late String _activeProfileKey;
  late final AppRouter _appRouter;
  bool _switchingSyncProfile = false;

  @override
  void initState() {
    super.initState();

    _officialApiConfig = PapyrusApiConfig.fromEnvironment();
    _syncSettingsProvider = SyncSettingsProvider(widget.prefs, officialConfig: _officialApiConfig);
    _activeProfileKey = _syncSettingsProvider.activeProfileKey;
    _authRepository = _buildAuthRepository(_syncSettingsProvider.activeApiConfig, _activeProfileKey);

    _dataStore = DataStore();
    _mediaUploadQueue = MediaUploadQueue(widget.prefs);
    _bookImportService = BookImportService();
    _authProvider = AuthProvider(widget.prefs, repository: _authRepository);
    _powerSyncService = PapyrusPowerSyncService(
      connectorFactory: () => PapyrusPowerSyncConnector(
        authRepository: _authRepository,
        config: _syncSettingsProvider.activeApiConfig,
        onUploadComplete: _processMediaUploads,
      ),
    );
    unawaited(_dataStore.attachBookRepository(_powerSyncService));
    _appRouter = AppRouter(authProvider: _authProvider);
    _authProvider.addListener(_syncPowerSyncAuthState);
    _syncSettingsProvider.addListener(_handleSyncSettingsChanged);
    _syncPowerSyncAuthState();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_syncPowerSyncAuthState);
    _syncSettingsProvider.removeListener(_handleSyncSettingsChanged);
    unawaited(_disposeDataServices());
    _bookImportService.dispose();
    _authProvider.dispose();
    _syncSettingsProvider.dispose();
    super.dispose();
  }

  AuthRepository _buildAuthRepository(PapyrusApiConfig config, String profileKey) {
    final tokenStore = TokenStore(SecureRefreshTokenStorage.scoped(profileKey));
    return AuthRepository(
      apiClient: AuthApiClient(config: config),
      tokenStore: tokenStore,
    );
  }

  Future<void> _disposeDataServices() async {
    await _dataStore.disposeBookRepository();
    await _powerSyncService.close();
  }

  void _syncPowerSyncAuthState() {
    final user = _authProvider.user;
    if (user != null && !_authProvider.isOfflineMode) {
      final userId = user.userId;
      unawaited(_powerSyncService.activateAuthenticated(userId, profileKey: _activeProfileKey));
      unawaited(_refreshMediaUsage());
      unawaited(_processMediaUploads());
      return;
    }

    if (_authProvider.isOfflineMode) {
      unawaited(_powerSyncService.activateGuest());
      return;
    }

    if (!_authProvider.isBootstrapping && _powerSyncService.mode != null) {
      unawaited(_powerSyncService.deactivate(clearAuthenticated: !_switchingSyncProfile));
    }
  }

  void _handleSyncSettingsChanged() {
    final nextProfileKey = _syncSettingsProvider.activeProfileKey;
    if (nextProfileKey == _activeProfileKey) {
      return;
    }

    _activeProfileKey = nextProfileKey;
    unawaited(_switchActiveSyncProfile());
  }

  Future<void> _switchActiveSyncProfile() async {
    _switchingSyncProfile = true;
    try {
      await _powerSyncService.deactivate(clearAuthenticated: false);
      _authRepository = _buildAuthRepository(_syncSettingsProvider.activeApiConfig, _activeProfileKey);
      await _authProvider.replaceRepository(_authRepository, bootstrapNewRepository: !_authProvider.isOfflineMode);
      unawaited(_refreshMediaUsage());
    } finally {
      _switchingSyncProfile = false;
      _syncPowerSyncAuthState();
    }
  }

  Future<void> _refreshMediaUsage() async {
    if (!_authProvider.isSignedIn || _authProvider.isOfflineMode) return;
    try {
      await _mediaUploadQueue.refreshUsage(_authRepository.fetchMediaUsage);
    } catch (_) {
      // Usage is informational; failed refresh must not block data sync.
    }
  }

  Future<void> _processMediaUploads() async {
    if (!_authProvider.isSignedIn || _authProvider.isOfflineMode) return;
    await _mediaUploadQueue.processPending(
      dataStore: _dataStore,
      readBookFile: _bookImportService.getBookFile,
      uploadMedia: (payload) async {
        try {
          return await _authRepository.uploadMedia(payload);
        } on AuthApiException catch (error) {
          if (error.statusCode == 409) {
            throw const MediaUploadException.storageFull();
          }
          rethrow;
        }
      },
    );
    await _refreshMediaUsage();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core data store - single source of truth
        ChangeNotifierProvider.value(value: _dataStore),
        ChangeNotifierProvider.value(value: _mediaUploadQueue),
        ChangeNotifierProvider.value(value: _syncSettingsProvider),
        Provider.value(value: _powerSyncService),
        Provider.value(value: _bookImportService),
        Provider(create: _createBookDownloadService),
        Provider(create: _createMediaCacheService),
        StreamProvider<SyncState>.value(value: _powerSyncService.syncStates, initialData: _powerSyncService.syncState),
        // Auth and UI state providers
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider(create: (_) => SidebarProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider(widget.prefs)),
      ],
      child: Consumer<PreferencesProvider>(
        builder: (context, preferencesProvider, child) {
          final isEink = preferencesProvider.isEinkMode;
          return MaterialApp.router(
            title: 'Papyrus',
            debugShowCheckedModeBanner: false,
            theme: isEink ? AppTheme.eink : AppTheme.light,
            darkTheme: isEink ? AppTheme.eink : AppTheme.dark,
            themeMode: isEink ? ThemeMode.light : preferencesProvider.themeMode,
            routerConfig: _appRouter.router,
          );
        },
      ),
    );
  }
}

BookDownloadService _createBookDownloadService(BuildContext _) => const BookDownloadService();

MediaCacheService _createMediaCacheService(BuildContext _) => const MediaCacheService();
