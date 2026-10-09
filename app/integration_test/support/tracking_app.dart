import 'package:papyrus/services/reading_device_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/pages/goals_page.dart';
import 'package:papyrus/pages/reader_page.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:powersync/powersync.dart' hide Column;

class NoNetworkConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

class FixtureMediaCache extends MediaCacheService {
  FixtureMediaCache(this.bytes);
  final Map<String, Uint8List> bytes;

  @override
  Future<Uint8List> ensureBookFileCached(
    Book book, {
    required LocalBookFileReader readLocalBookFile,
    required LocalBookFileWriter writeLocalBookFile,
    required MediaDownloader downloadMedia,
  }) async => bytes[book.id]!;
}

class FixtureAuth extends ChangeNotifier implements AuthProvider {
  @override
  Future<Uint8List> downloadMedia(String assetId) async => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackingValidationApp {
  late final PapyrusPowerSyncService database;
  late final DataStore store;
  late final GoalsProvider goals;
  late final PreferencesProvider preferences;
  late final GoRouter router;
  final bytes = <String, Uint8List>{};
  final fixtureAuth = FixtureAuth();

  Future<void> initialize() async {
    const origin = String.fromEnvironment('TRACKING_FIXTURE_ORIGIN', defaultValue: 'http://127.0.0.1:7311');

    for (final format in ['epub', 'pdf']) {
      final response = await http.get(Uri.parse('$origin/reader.$format'));

      if (response.statusCode != 200) {
        throw StateError('Fixture $format could not load');
      }

      bytes[format] = response.bodyBytes;
    }

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final root = kIsWeb ? '' : (await getApplicationSupportDirectory()).path;

    database = PapyrusPowerSyncService(
      connectorFactory: NoNetworkConnector.new,
      connectAuthenticated: false,
      pathResolver: (_, _, _) async => '${root.isEmpty ? '' : '$root/'}goals-validation-$suffix.db',
    );

    await database.activateGuest();

    for (final format in [BookFormat.epub, BookFormat.pdf]) {
      await database.upsert(
        Book(
          id: format.name,
          title: format == BookFormat.epub
              ? 'Alice’s Adventures in Wonderland'
              : 'Structure and Interpretation of Computer Programs',
          author: '',
          addedAt: DateTime.now().toUtc(),
          fileFormat: format,
          pageCount: 200,
        ),
      );
    }

    store = DataStore(bookRepository: database);
    await store.waitUntilLoaded();
    goals = GoalsProvider(watchClock: false)..attach(store);
    await goals.createGoal(type: GoalType.minutes, target: 30, period: GoalPeriod.daily, timezone: 'Europe/Vilnius');
    await goals.createGoal(type: GoalType.days, target: 5, period: GoalPeriod.weekly, timezone: 'Europe/Vilnius');
    await goals.createGoal(type: GoalType.pages, target: 100, period: GoalPeriod.weekly, timezone: 'Europe/Vilnius');
    final prefs = await SharedPreferences.getInstance();
    await ReadingDeviceIdentity.initialize(prefs);
    preferences = PreferencesProvider(prefs);

    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          name: 'BOOKS',
          builder: (_, _) => Scaffold(
            body: Column(
              children: [
                Wrap(
                  children: [
                    for (final format in ['epub', 'pdf'])
                      TextButton(
                        onPressed: () => router.goNamed('BOOK_READER', pathParameters: {'bookId': format}),
                        child: Text('Open $format'),
                      ),
                  ],
                ),
                const Expanded(child: GoalsPage()),
              ],
            ),
          ),
        ),
        GoRoute(path: '/book/:bookId', name: 'BOOK_DETAILS', redirect: (_, _) => '/'),
        GoRoute(
          path: '/reader/:bookId',
          name: 'BOOK_READER',
          builder: (_, state) => ReaderPage(bookId: state.pathParameters['bookId']!),
        ),
      ],
    );
  }

  Widget build({ThemeData? theme, double textScale = 1}) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: store),
      ChangeNotifierProvider.value(value: preferences),
      Provider<MediaCacheService>.value(value: FixtureMediaCache(bytes)),
      Provider<BookImportService>(create: (_) => BookImportService()),
      ChangeNotifierProvider<AuthProvider>.value(value: fixtureAuth),
    ],
    child: MaterialApp.router(
      theme: theme ?? AppTheme.dark,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );

  Future<void> close() async {
    goals.dispose();
    router.dispose();
    store.dispose();
    preferences.dispose();
    fixtureAuth.dispose();
    await database.clearGuestLibrary();
    await database.close();
  }
}
