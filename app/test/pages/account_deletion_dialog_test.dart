import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/auth/oauth_callback_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/widgets/profile/account_settings_section.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage implements RefreshTokenStorage {
  String? value = 'refresh';

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

class _Repository extends AuthRepository {
  _Repository({required super.apiClient, required super.tokenStore, required this.connected});

  final bool connected;

  @override
  Future<AuthTokens?> bootstrap() async => AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: 'user',
      email: 'reader@example.com',
      displayName: 'Reader',
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
      connectedProviders: connected ? ['google'] : [],
    ),
  );
}

void main() {
  late AuthProvider auth;
  late _Storage storage;
  late List<http.Request> requests;
  var pending = false;
  var failSchedule = false;
  var expired = false;

  Future<void> setup({bool signedIn = true, bool connected = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = _Storage();
    requests = [];

    final api = AuthApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://server.test')),
      httpClient: MockClient((request) async {
        requests.add(request);

        final authorization = {
          'authorization_token': 'restricted-token',
          'user_id': 'user',
          'email': 'reader@example.com',
          'deletion_pending': pending,
          'deletion_due_at': '2026-11-22T12:00:00Z',
          'expires_at': DateTime.now().add(Duration(minutes: expired ? -1 : 5)).toIso8601String(),
        };

        if ((request.url.path.endsWith('/login') || request.url.path.endsWith('/exchange-code')) && pending) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'ACCOUNT_DELETION_PENDING',
                'message': 'This account is scheduled for deletion.',
                'details': {'authorization': authorization},
              },
            }),
            403,
          );
        }

        if (failSchedule) {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Try again later'},
            }),
            503,
          );
        }

        return http.Response(
          jsonEncode(
            pending
                ? {
                    'access_token': 'restored-access',
                    'refresh_token': 'restored-refresh',
                    'expires_in': 3600,
                    'user': {
                      'user_id': 'user',
                      'email': 'reader@example.com',
                      'display_name': 'Reader',
                      'email_verified': true,
                      'connected_providers': connected ? ['google'] : [],
                    },
                  }
                : {'deletion_due_at': '2026-11-22T12:00:00Z', 'message': 'Deletion scheduled.'},
          ),
          200,
        );
      }),
    );

    auth = AuthProvider(
      prefs,
      repository: _Repository(
        apiClient: api,
        tokenStore: TokenStore(storage)..setAccessToken('access'),
        connected: connected,
      ),
      bootstrapOnCreate: false,
    );

    if (signedIn) {
      await auth.bootstrap();
    }

    addTearDown(auth.dispose);
  }

  Future<void> showPage(WidgetTester tester, {bool desktop = false, bool login = false, String? callback}) async {
    final router = GoRouter(
      initialLocation: callback ?? (login ? '/login' : '/profile'),
      refreshListenable: auth,
      redirect: (_, state) => state.uri.path == '/profile' && !auth.isSignedIn ? '/login' : null,
      routes: [
        GoRoute(
          path: '/auth/callback',
          builder: (_, state) => OAuthCallbackPage(callbackUri: state.uri),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(child: AccountSettingsSection(isDesktop: desktop)),
          ),
        ),
        GoRoute(
          path: '/library',
          name: 'LIBRARY',
          builder: (_, _) => const Scaffold(body: Text('Your library')),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    pending = false;
    failSchedule = false;
    expired = false;
  });

  for (final desktop in [false, true]) {
    testWidgets('Google deletion completes in the existing session, desktop=$desktop', (tester) async {
      await setup(connected: true);
      final size = Size(desktop ? 1200 : 360, 800);
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetPhysicalSize);
      await showPage(tester, desktop: desktop);
      expect(find.text('Connected'), findsOneWidget);

      for (final label in ['Change password', 'Two-factor authentication', 'Active sessions']) {
        final row = find.widgetWithText(SettingsRow, label);
        final ink = tester.widget<InkWell>(find.descendant(of: row, matching: find.byType(InkWell)));
        expect(ink.onTap, isNull);
        expect(ink.canRequestFocus, isFalse);
      }

      await openDialog(tester);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(find.text('Confirm it’s you'), findsNothing);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(requests, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.isSignedIn, isTrue);
      expect(requests, isEmpty);
      await openDialog(tester);
      await confirm(tester);
      expect(auth.isSignedIn, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests.map((request) => request.url.path), [
        '/v1/account-deletion/current',
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('password account deletion uses the current session without another password prompt', (tester) async {
    await setup();
    await showPage(tester);
    await openDialog(tester);
    await confirm(tester);
    expect(find.textContaining('Account deletion scheduled for Nov 22, 2026'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    expect(storage.value, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests.single.url.path, '/v1/account-deletion/current');
    expect(requests.single.headers['Authorization'], 'Bearer access');
  });

  testWidgets('failed deletion keeps the account signed in and permits retry', (tester) async {
    await setup();
    failSchedule = true;
    await showPage(tester);
    await openDialog(tester);
    await confirm(tester);
    expect(find.text('Try again later'), findsOneWidget);
    expect(auth.isSignedIn, isTrue);
    expect(storage.value, 'refresh');
    failSchedule = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Account deletion scheduled for'), findsOneWidget);
    expect(requests.map((request) => request.url.path), [
      '/v1/account-deletion/current',
      '/v1/account-deletion/current',
    ]);
  });

  testWidgets('normal login offers recovery without another password prompt', (tester) async {
    pending = true;
    await setup(signedIn: false);
    await showPage(tester, login: true);
    await tester.enterText(find.byType(TextFormField).first, 'reader@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'current-password');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your account?'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    expect(requests.where((request) => request.url.path.endsWith('/cancel')), isEmpty);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(requests.where((request) => request.url.path.endsWith('/cancel')), isEmpty);
    await tester.enterText(find.byType(TextFormField).last, 'current-password');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(auth.isSignedIn, isTrue);
    expect(storage.value, 'restored-refresh');
    expect(find.byType(LoginPage), findsNothing);
    expect(requests.where((request) => request.url.path.endsWith('/cancel')), hasLength(1));
  });

  testWidgets('Google sign-in callback offers recovery and leaves it pending on dismissal', (tester) async {
    pending = true;
    await setup(signedIn: false);
    await showPage(tester, callback: '/auth/callback?code=login-code');
    expect(find.text('Keep your account?'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(requests.where((request) => request.url.path.endsWith('/cancel')), isEmpty);
  });

  testWidgets('Google sign-in recovery opens the library without signing in twice', (tester) async {
    pending = true;
    await setup(signedIn: false, connected: true);
    await showPage(tester, callback: '/auth/callback?code=login-code');
    expect(find.text('Keep your account?'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    failSchedule = true;
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
    expect(find.text('Try again later'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    failSchedule = false;
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(auth.isSignedIn, isTrue);
    expect(storage.value, 'restored-refresh');
    expect(requests.where((request) => request.url.path.endsWith('/exchange-code')), hasLength(1));
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('expired recovery proof does not restore the account', (tester) async {
    expired = true;
    pending = true;
    await setup(signedIn: false);
    await showPage(tester, callback: '/auth/callback?code=login-code');
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
    expect(find.text('Verification expired. Close this dialog and try again.'), findsOneWidget);
    expect(requests.where((request) => request.url.path.endsWith('/cancel')), isEmpty);
    expect(auth.isSignedIn, isFalse);
  });
}
