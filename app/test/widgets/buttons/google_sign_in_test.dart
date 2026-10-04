import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/register_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/auth/auth_switch_link.dart';
import 'package:papyrus/widgets/buttons/google_sign_in.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_router_test.dart' show MemoryRefreshTokenStorage;

class _PendingGoogleRepository extends AuthRepository {
  _PendingGoogleRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test'))),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

  final pending = Completer<AuthTokens?>();
  int requests = 0;

  @override
  Future<AuthTokens?> bootstrap() async => null;

  @override
  Future<AuthTokens?> signInWithGoogle({required String clientType, String? deviceLabel}) {
    requests++;
    return pending.future;
  }
}

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final layout in [(screen: const Size(400, 1400), scale: 1.0), (screen: const Size(1200, 1200), scale: 1.0)]) {
      for (final page in [const LoginPage(), const RegisterPage()]) {
        testWidgets(
          'Google loading preserves ${page.runtimeType} geometry at ${layout.screen.width}, ${theme.brightness}',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = layout.screen;
            addTearDown(tester.view.reset);
            final repository = _PendingGoogleRepository();
            final auth = AuthProvider(
              await SharedPreferences.getInstance(),
              repository: repository,
              bootstrapOnCreate: false,
            );
            await auth.bootstrap();
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              auth.dispose();
            });
            await tester.pumpWidget(
              ChangeNotifierProvider.value(
                value: auth,
                child: MaterialApp(
                  theme: theme,
                  home: page,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: child!,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final button = find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(OutlinedButton));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final buttonBounds = tester.getRect(button);
            final title = page is LoginPage ? 'Sign in with Google' : 'Sign up with Google';
            final labelBounds = tester.getRect(find.text(title));
            final footerBounds = tester.getRect(find.byType(AuthSwitchLink).first);
            await tester.tap(button);
            await tester.pump();
            expect(tester.getRect(button), buttonBounds);
            expect(tester.getRect(find.text(title)), labelBounds);
            expect(tester.getRect(find.byType(AuthSwitchLink).first), footerBounds);
            expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
            expect(find.descendant(of: button, matching: find.byType(AppCircularProgressIndicator)), findsOneWidget);
            await tester.tap(button);
            await tester.pump(const Duration(milliseconds: 100));
            expect(repository.requests, 1);
            expect(tester.getRect(button), buttonBounds);
            repository.pending.completeError(const AuthApiException(statusCode: 503, message: 'Try again later.'));
            await tester.pump();
            await tester.pump();
            expect(tester.getRect(button), buttonBounds);
            expect(tester.getRect(find.text(title)), labelBounds);
            expect(tester.getRect(find.byType(AuthSwitchLink).first), footerBounds);
            expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
            expect(find.byType(AppCircularProgressIndicator), findsNothing);
            expect(find.text('Try again later.'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    testWidgets('Google loading keeps button size at enlarged text in ${theme.brightness}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = _PendingGoogleRepository();
      final auth = AuthProvider(
        await SharedPreferences.getInstance(),
        repository: repository,
        bootstrapOnCreate: false,
      );
      await auth.bootstrap();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(size: Size(400, 1000), textScaler: TextScaler.linear(2)),
                child: const Center(
                  child: SizedBox(width: 320, child: GoogleSignInButton(title: 'Sign in with Google')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byType(OutlinedButton);
      final bounds = tester.getRect(button);
      final labelBounds = tester.getRect(find.text('Sign in with Google'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.getRect(button), bounds);
      expect(tester.getRect(find.text('Sign in with Google')), labelBounds);
      expect(find.byType(AppCircularProgressIndicator), findsOneWidget);
      repository.pending.complete(null);
      await tester.pump();
      expect(tester.getRect(button), bounds);
      expect(find.byType(AppCircularProgressIndicator), findsNothing);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
