import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/pages/auth/verification_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/pending_verification_test.dart' show repository, response;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AuthProvider> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    String? token,
    bool isLink = true,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(
      await SharedPreferences.getInstance(),
      repository: repository(handler),
      bootstrapOnCreate: false,
    );
    final router = GoRouter(
      initialLocation: '/verify-email',
      routes: [
        GoRoute(
          path: '/verify-email',
          builder: (_, _) => VerificationPage(token: token, isLink: isLink),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Fresh sign-in')),
        ),
        GoRoute(
          name: 'LIBRARY',
          path: '/library',
          builder: (_, _) => const Scaffold(body: Text('Library')),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      auth.dispose();
    });
    return auth;
  }

  for (final size in [const Size(320, 700), const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('confirmation is explicit and keyboard accessible at $size', (tester) async {
      final semantics = tester.ensureSemantics();
      var calls = 0;
      final auth = await mount(
        tester,
        (request) async {
          calls += 1;
          expect(request.url.path, '/custom/api/auth/verify-email');
          expect(jsonDecode(request.body), {'token': 'opaque-token'});
          return response({'message': 'Email verified successfully'});
        },
        token: 'opaque-token',
        size: size,
      );
      expect(calls, 0);
      expect(find.text('Confirm email address'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm email address'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Email verified'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('You can now sign in to Papyrus.'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(auth.isSignedIn, isFalse);
      expect(find.text('Confirm email address'), findsNothing);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh sign-in'), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid, expired and already-used links offer resend and sign-in', (tester) async {
    final semantics = tester.ensureSemantics();
    final auth = await mount(
      tester,
      (_) async => response({
        'error': {
          'code': 'VERIFICATION_TOKEN_INVALID',
          'message': 'This verification link is invalid or expired.',
          'details': {},
        },
      }, 400),
      token: 'expired',
    );
    await tester.ensureVisible(find.text('Confirm email address'));
    await tester.tap(find.text('Confirm email address'));
    await tester.pumpAndSettle();
    expect(find.text('Resend verification email'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.textContaining('This link cannot be used'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.text('Back to sign in'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure retains explicit confirmation for retry', (tester) async {
    var calls = 0;
    await mount(tester, (_) async {
      calls += 1;
      if (calls == 1) throw http.ClientException('offline');
      return response({'message': 'Email verified successfully'});
    }, token: 'retry');
    await tester.ensureVisible(find.text('Confirm email address'));
    await tester.tap(find.text('Confirm email address'));
    await tester.pumpAndSettle();
    expect(find.text('Authentication request failed. Please try again.'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm email address'));
    await tester.tap(find.text('Confirm email address'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('resend cooldown and enlarged text preserve actionable controls', (tester) async {
    var calls = 0;
    await mount(
      tester,
      (_) async {
        calls += 1;
        return response({'message': 'Request accepted', 'resend_after': 60});
      },
      isLink: false,
      size: const Size(320, 700),
      scale: 1.6,
    );
    await tester.enterText(find.byType(TextFormField), 'alice@example.com');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Resend verification email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rate limit responses disable retries', (tester) async {
    await mount(
      tester,
      (_) async => response({
        'error': {
          'code': 'RATE_LIMIT_EXCEEDED',
          'message': 'Too many requests',
          'details': {'retry_after': 35},
        },
      }, 429),
      isLink: false,
    );
    await tester.enterText(find.byType(TextFormField), 'alice@example.com');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Resend verification email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Try again in'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });

  testWidgets('resend delivery failure remains visible after an invalid link', (tester) async {
    await mount(tester, (request) async {
      if (request.url.path.endsWith('/verify-email')) {
        return response({
          'error': {'code': 'VERIFICATION_TOKEN_INVALID', 'message': 'Invalid link', 'details': {}},
        }, 400);
      }

      return response(
        {
          'error': {
            'code': 'VERIFICATION_UNAVAILABLE',
            'message': 'Verification email is temporarily unavailable. Please try again later.',
            'details': {},
          },
        },
        503,
        {'retry-after': '60'},
      );
    }, token: 'expired');
    await tester.ensureVisible(find.text('Confirm email address'));
    await tester.tap(find.text('Confirm email address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'alice@example.com');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Resend verification email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(
      find.text('We couldn’t send the verification email. Try again, or contact your server administrator.'),
      findsOneWidget,
    );
    expect(find.textContaining('Try again in'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });

  testWidgets('server change discards the captured token and pending email', (tester) async {
    var calls = 0;
    final auth = await mount(tester, (_) async {
      calls += 1;
      return response({'message': 'Verified'});
    }, token: 'private');
    await auth.replaceRepository(
      repository((_) async => fail('Must not send to new server'), server: 'two'),
      bootstrapNewRepository: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm email address'), findsNothing);
    expect(find.textContaining('different server'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('leaving during confirmation ignores a late response', (tester) async {
    final completed = Completer<http.Response>();
    final auth = await mount(tester, (_) => completed.future, token: 'private');
    await tester.ensureVisible(find.text('Confirm email address'));
    await tester.tap(find.text('Confirm email address'));
    await tester.pump();
    await tester.ensureVisible(find.text('Back to sign in'));
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    completed.complete(response({'message': 'Verified'}));
    await tester.pumpAndSettle();
    expect(find.text('Fresh sign-in'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    expect(auth.error, isNull);
  });
}
