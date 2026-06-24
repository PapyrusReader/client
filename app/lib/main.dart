import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
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
  late final PapyrusPowerSyncService _powerSyncService;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();

    final apiConfig = PapyrusApiConfig.fromEnvironment();
    final tokenStore = TokenStore(const SecureRefreshTokenStorage());
    final authRepository = AuthRepository(
      apiClient: AuthApiClient(config: apiConfig),
      tokenStore: tokenStore,
    );

    _dataStore = DataStore();
    _authProvider = AuthProvider(widget.prefs, repository: authRepository);
    _powerSyncService = PapyrusPowerSyncService(
      connectorFactory: () => PapyrusPowerSyncConnector(authRepository: authRepository, config: apiConfig),
    );
    unawaited(_dataStore.attachBookRepository(_powerSyncService));
    _appRouter = AppRouter(authProvider: _authProvider);
    _authProvider.addListener(_syncPowerSyncAuthState);
    _syncPowerSyncAuthState();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_syncPowerSyncAuthState);
    unawaited(_disposeDataServices());
    _authProvider.dispose();
    super.dispose();
  }

  Future<void> _disposeDataServices() async {
    await _dataStore.disposeBookRepository();
    await _powerSyncService.close();
  }

  void _syncPowerSyncAuthState() {
    final user = _authProvider.user;
    if (user != null && !_authProvider.isOfflineMode) {
      final userId = user.userId;
      unawaited(_powerSyncService.activateAuthenticated(userId));
      return;
    }

    if (_authProvider.isOfflineMode) {
      unawaited(_powerSyncService.activateGuest());
      return;
    }

    if (!_authProvider.isBootstrapping) {
      unawaited(_powerSyncService.deactivate());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core data store - single source of truth
        ChangeNotifierProvider.value(value: _dataStore),
        Provider.value(value: _powerSyncService),
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
