import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/admin/user_directory.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/admin_users_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_router_test.dart' show MemoryRefreshTokenStorage;

final config = PapyrusApiConfig(serverBaseUri: Uri.parse('https://example.test'), apiPrefix: '/custom');

Future<(AuthProvider, SyncSettingsProvider)> mount(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) respond, {
  Size size = const Size(1280, 800),
  double scale = 1,
  GoRouter? router,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final repository = AuthRepository(
    apiClient: AuthApiClient(
      config: config,
      httpClient: MockClient((request) async {
        if (request.url.path == '/custom/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'user_id': 'admin',
                'display_name': 'Admin',
                'email_verified': true,
                'role': 'admin',
                'connected_providers': [],
              },
            }),
            200,
          );
        }

        expect(request.url.path, '/custom/admin/users');
        expect(request.headers['Authorization'], 'Bearer access');
        expect(request.url.queryParameters['limit'], '20');
        return respond(request);
      }),
    ),
    tokenStore: TokenStore(MemoryRefreshTokenStorage()),
  );

  final auth = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);
  await auth.login(email: 'admin@example.test', password: 'test');

  final settings = SyncSettingsProvider(
    prefs,
    officialConfig: config,
    discoveryFetcher: (server) async => DataSyncDiscoverySettings(dataSyncUri: server, fileStorageQuotaBytes: null),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: settings),
        if (router != null) ...[
          ChangeNotifierProvider(create: (_) => DataStore()),
          ChangeNotifierProvider(create: (_) => SidebarProvider()),
          ChangeNotifierProvider(create: (_) => OpdsCatalogs(OpdsCatalogStore(prefs))),
        ],
      ],
      child: router != null
          ? MaterialApp.router(routerConfig: router)
          : MaterialApp(
              theme: scale > 1 ? AppTheme.eink : AppTheme.light,
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: const AdminUsersPage(),
                ),
              ),
            ),
    ),
  );

  await tester.pump();
  return (auth, settings);
}

http.Response directory(int page, {int total = 21}) {
  final offset = (page - 1) * 20;
  return http.Response(
    jsonEncode({
      'pagination': {'page': page, 'limit': 20, 'total': total},
      'quota_bytes': 1073741824,
      'users': [
        for (var index = offset; index < offset + 20 && index < total; index++)
          {
            'user_id': 'account-$index',
            'display_name': 'Reader ${index + 1}',
            'email': 'reader${index + 1}@example.test',
            'role': 'user',
            'status': 'active',
            'created_at': '2026-10-01T00:00:00Z',
            'last_sign_in_at': index == 0 ? '2026-11-15T12:30:00Z' : null,
            'book_count': index == 0 ? 2 : 0,
            'used_bytes': index == 0 ? 268435456 : 0,
          },
      ],
    }),
    200,
  );
}

void main() {
  test('absent and unknown roles grant ordinary access', () {
    final user = <String, dynamic>{'user_id': 'reader', 'connected_providers': []};
    expect(PapyrusUser.fromJson(user).isAdmin, isFalse);
    expect(PapyrusUser.fromJson({...user, 'role': 'operator'}).isAdmin, isFalse);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('Administration expands in the main menu and opens Users at ${width}px', (tester) async {
      final router = GoRouter(
        initialLocation: '/library/books',
        routes: [
          ShellRoute(
            builder: (_, _, child) => AdaptiveAppShell(child: child),
            routes: [
              GoRoute(path: '/library/books', builder: (_, _) => const Text('Library content')),
              GoRoute(path: '/admin/users', builder: (_, _) => const AdminUsersPage()),
            ],
          ),
        ],
      );

      addTearDown(router.dispose);
      final (auth, _) = await mount(
        tester,
        (_) async => directory(1, total: 1),
        size: Size(width, 1000),
        router: router,
      );
      await tester.pumpAndSettle();

      if (width < 840) {
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.bySemanticsLabel('Collapse sidebar'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Administration'));
        await tester.pumpAndSettle();
        expect(find.text('Users'), findsOneWidget);
        await tester.tap(find.text('Administration'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Users'), findsNothing);
      await tester.ensureVisible(find.text('Administration'));
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/library/books');
      await tester.ensureVisible(find.text('Users'));
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      final usersPage = tester.element(find.byType(AdminUsersPage));
      expect(GoRouterState.of(usersPage).uri.path, '/admin/users');
      expect(find.text('Reader 1'), findsOneWidget);

      if (width < 840) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Library content'), findsOneWidget);
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
      }

      auth.setOfflineMode(true);
      await tester.pumpAndSettle();
      expect(find.text('Administration'), findsNothing);
      expect(find.text('Users'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide directory shows quota, averages and server-paginated results', (tester) async {
    final requests = <Map<String, String>>[];
    final nextPage = Completer<http.Response>();

    await mount(tester, (request) async {
      requests.add(request.url.queryParameters);

      if (requests.length == 2) {
        return nextPage.future;
      }

      return directory(int.parse(request.url.queryParameters['page']!));
    });
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.columns.map((column) => (column.label as Text).data), [
      'Name',
      'Email',
      'Status',
      'Joined',
      'Last sign-in',
      'Books',
      'Storage used',
      'Quota used',
      'Average per book',
    ]);
    expect(table.rows.first.cells.take(3).map((cell) => (cell.child as Text).data), [
      'Reader 1',
      'reader1@example.test',
      'Active',
    ]);
    expect(find.textContaining('Storage quota per user'), findsNothing);
    expect(find.text('256 MiB'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('128 MiB'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value, .25);
    await tester.scrollUntilVisible(find.byTooltip('Next page'), 500, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final tableElement = tester.element(find.byType(DataTable));
    final pagerPosition = tester.getTopLeft(find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    expect(tester.element(find.byType(DataTable)), same(tableElement));
    expect(tester.getTopLeft(find.byTooltip('Next page')), pagerPosition);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    nextPage.complete(directory(2));
    await tester.pumpAndSettle();
    expect(find.text('21 of 21 users'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Reader 21'), findsOneWidget);
    expect(find.text('Reader 1'), findsNothing);
    expect(find.text('No sign-in recorded'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(requests.last, {'page': '1', 'limit': '20', 'sort_by': 'display_name', 'descending': 'false'});
    expect(find.text('Reader 1'), findsOneWidget);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(requests.last['descending'], 'true');
    await tester.scrollUntilVisible(find.byTooltip('Next page'), 500, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(requests.last, {'page': '2', 'limit': '20', 'sort_by': 'display_name', 'descending': 'true'});
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Reader 1'), findsOneWidget);
  });

  testWidgets('compact e-ink layout handles large text and retry', (tester) async {
    var attempts = 0;
    final requests = <Map<String, String>>[];

    await mount(
      tester,
      (request) async {
        requests.add(request.url.queryParameters);
        return ++attempts == 1 ? http.Response('{}', 503) : directory(1, total: 1);
      },
      size: const Size(360, 900),
      scale: 1.6,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);
    await tester.tap(find.byTooltip('Sort users by'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<DirectoryColumn>, 'Email'));
    await tester.pumpAndSettle();
    expect(requests.last['sort_by'], 'email');
    await tester.tap(find.byTooltip('Sort descending'));
    await tester.pumpAndSettle();
    expect(requests.last['descending'], 'true');
    expect(find.text('256 MiB'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sorting retains rows through failure and retry and ignores superseded responses', (tester) async {
    final slowName = Completer<http.Response>();
    final failedEmail = Completer<http.Response>();
    var emailAttempts = 0;

    await mount(tester, (request) async {
      switch (request.url.queryParameters['sort_by']) {
        case 'display_name':
          return slowName.future;
        case 'email':
          if (++emailAttempts == 1) {
            return failedEmail.future;
          }

          return directory(1, total: 2);
        default:
          return directory(1, total: 1);
      }
    });

    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(find.text('Reader 1'), findsOneWidget);
    await tester.tap(find.text('Email'));
    await tester.pump();
    failedEmail.complete(http.Response('{}', 503));
    await tester.pumpAndSettle();
    expect(find.text('Reader 1'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex, DirectoryColumn.joined.index);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Reader 2'), findsOneWidget);
    slowName.complete(directory(1, total: 1));
    await tester.pumpAndSettle();
    expect(find.text('Reader 2'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex, DirectoryColumn.email.index);
  });

  testWidgets('switching server while loading discards the previous directory', (tester) async {
    final pending = Completer<http.Response>();
    final (_, settings) = await mount(tester, (request) async {
      return request.url.queryParameters['sort_by'] == 'display_name' ? pending.future : directory(1, total: 1);
    });

    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(find.text('Reader 1'), findsOneWidget);
    await settings.addCustomServer(config.serverBaseUri.toString());
    await tester.pump();
    pending.complete(directory(1, total: 1));
    await tester.pumpAndSettle();
    expect(find.text('Users'), findsNothing);
    expect(find.text('Reader 1'), findsNothing);
  });

  testWidgets('server denial clears the directory and removes admin access', (tester) async {
    final (auth, settings) = await mount(tester, (request) async {
      return request.url.queryParameters['sort_by'] == 'display_name'
          ? http.Response('{}', 403)
          : directory(1, total: 1);
    });

    await tester.pumpAndSettle();
    expect(find.text('Reader 1'), findsOneWidget);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(auth.canAdminister(settings), isFalse);
    expect(find.text('Users'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}
