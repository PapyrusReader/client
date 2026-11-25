import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      ],
      child: MaterialApp(
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

  testWidgets('wide directory shows quota, averages and server-paginated results', (tester) async {
    await mount(tester, (request) async => directory(int.parse(request.url.queryParameters['page']!)));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('256 MiB of 1 GiB · 25%'), findsOneWidget);
    expect(find.text('128 MiB'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value, .25);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('21 of 21 users'), findsOneWidget);
    expect(find.text('Reader 21'), findsOneWidget);
    expect(find.text('Reader 1'), findsNothing);
    expect(find.text('No sign-in recorded'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Reader 1'), findsOneWidget);
  });

  testWidgets('compact e-ink layout handles large text and retry', (tester) async {
    var attempts = 0;

    await mount(
      tester,
      (request) async => ++attempts == 1 ? http.Response('{}', 503) : directory(1, total: 1),
      size: const Size(360, 900),
      scale: 1.6,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsNothing);
    expect(find.text('256 MiB of 1 GiB · 25%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching server while loading discards the previous directory', (tester) async {
    final pending = Completer<http.Response>();
    final (_, settings) = await mount(tester, (_) => pending.future);
    await settings.addCustomServer(config.serverBaseUri.toString());
    await tester.pump();
    pending.complete(directory(1, total: 1));
    await tester.pumpAndSettle();
    expect(find.text('Users'), findsNothing);
    expect(find.text('Reader 1'), findsNothing);
  });

  testWidgets('server denial clears the directory and removes admin access', (tester) async {
    final (auth, settings) = await mount(tester, (_) async => http.Response('{}', 403));
    await tester.pumpAndSettle();
    expect(auth.canAdminister(settings), isFalse);
    expect(find.text('Users'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}
