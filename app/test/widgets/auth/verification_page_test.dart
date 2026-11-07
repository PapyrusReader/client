import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
    String? pendingEmail,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(
      await SharedPreferences.getInstance(),
      repository: repository((request) {
        if (pendingEmail != null && request.url.path.endsWith('/register')) {
          return Future.value(
            response({
              'status': 'verification_required',
              'email': pendingEmail,
              'message': 'Check your email',
              'resend_after': 0,
            }, 201),
          );
        }

        return handler(request);
      }),
      bootstrapOnCreate: false,
    );
    if (pendingEmail != null) {
      await auth.register(email: pendingEmail, password: 'password', displayName: 'Reader');
    }

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
          theme: theme ?? AppTheme.light,
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
    testWidgets('opening a link verifies once without signing in at $size', (tester) async {
      final semantics = tester.ensureSemantics();
      var calls = 0;
      final auth = await mount(
        tester,
        (request) async {
          calls += 1;
          expect(request.method, 'POST');
          expect(request.url.path, '/custom/api/auth/verify-email');
          expect(jsonDecode(request.body), {'token': 'opaque-token'});
          return response({'message': 'Email verified successfully'});
        },
        token: 'opaque-token',
        size: size,
      );
      await tester.pump(const Duration(seconds: 2));
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

  testWidgets('invalid, expired and already-used links show an error without a form', (tester) async {
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
    expect(find.text('Link unavailable'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Send verification link'), findsNothing);
    expect(find.text('Continue offline'), findsNothing);
    expect(
      tester
          .getSemantics(find.text('This link has expired or is no longer valid.'))
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

  testWidgets('network failure offers a manual retry without repeating automatically', (tester) async {
    var calls = 0;
    await mount(tester, (_) async {
      calls += 1;
      if (calls == 1) throw http.ClientException('offline');
      return response({'message': 'Email verified successfully'});
    }, token: 'retry');
    expect(find.text('Authentication request failed. Please try again.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('automatic verification respects rate limits without repeated requests', (tester) async {
    var calls = 0;
    await mount(tester, (_) async {
      calls += 1;
      return response({
        'error': {
          'code': 'RATE_LIMIT_EXCEEDED',
          'message': 'Too many requests',
          'details': {'retry_after': 35},
        },
      }, 429);
    }, token: 'limited');
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Try again')).onPressed, isNull);
    await tester.pump(const Duration(seconds: 36));
    expect(calls, 1);
    expect(find.text('Email verified'), findsNothing);
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
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Send verification link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send verification link'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.textContaining('Resend in'),
                  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
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
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Send verification link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send verification link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.textContaining('Resend in'),
                  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('resend delivery failure remains visible while waiting for verification', (tester) async {
    await mount(
      tester,
      (request) async {
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
      },
      isLink: false,
      pendingEmail: 'alice@example.com',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Resend email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend email'));
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t send the verification email. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.textContaining('Resend in'),
                  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
  });

  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    testWidgets(
      'waiting state keeps the address readable and secondary actions compact in ${theme.brightness} / ${theme.colorScheme.primary}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var calls = 0;
        const address = 'reader.with.a.long.address@example.com';
        await mount(
          tester,
          (request) async {
            calls += 1;
            expect(jsonDecode(request.body), {'email': address});
            return response({'message': 'Request accepted', 'resend_after': 60});
          },
          isLink: false,
          pendingEmail: address,
          size: const Size(320, 700),
          scale: 2,
          theme: theme,
        );
        expect(find.text('Check your email'), findsOneWidget);
        expect(
          find.text('Open the link sent to $address. Check your spam folder if it hasn’t arrived.', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('Use another email'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Back to sign in'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Continue offline'), findsNothing);
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Resend email'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Resend email'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('New link requested. Check your inbox.'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.text('New link requested. Check your inbox.'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('server change discards the captured token and pending email', (tester) async {
    var calls = 0;
    final completed = Completer<http.Response>();
    final auth = await mount(tester, (_) {
      calls += 1;
      return completed.future;
    }, token: 'private');
    await auth.replaceRepository(
      repository((_) async => fail('Must not send to new server'), server: 'two'),
      bootstrapNewRepository: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm email address'), findsNothing);
    expect(find.textContaining('different server'), findsOneWidget);
    expect(calls, 1);
    completed.complete(response({'message': 'Verified'}));
    await tester.pumpAndSettle();
    expect(find.text('Email verified'), findsNothing);
  });

  testWidgets('missing link offers a return to sign-in without a verification request', (tester) async {
    final auth = await mount(tester, (_) async => fail('No verification token'));
    expect(find.text('Link unavailable'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Continue offline'), findsNothing);
    await tester.ensureVisible(find.text('Back to sign in'));
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh sign-in'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('leaving during automatic verification ignores a late response', (tester) async {
    final completed = Completer<http.Response>();
    final auth = await mount(tester, (_) => completed.future, token: 'private');
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
