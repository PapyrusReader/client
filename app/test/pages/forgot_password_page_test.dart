import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/forgot_password_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
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

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test'))),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

  String? forgotPasswordEmail;
  String? resetToken;
  String? resetPasswordValue;

  @override
  Future<String> forgotPassword(String email) async {
    forgotPasswordEmail = email;
    return 'If the email is registered, a reset link has been sent';
  }

  @override
  Future<String> resetPassword({required String token, required String password}) async {
    resetToken = token;
    resetPasswordValue = password;
    return 'Password has been reset successfully';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void setViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<FakeAuthRepository> pumpPage(WidgetTester tester, {String? resetToken, bool isResetLink = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = FakeAuthRepository();
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => provider,
        child: MaterialApp(
          home: ForgotPasswordPage(resetToken: resetToken, isResetLink: isResetLink),
        ),
      ),
    );

    return repository;
  }

  testWidgets('forgot password request shows check email state without token field', (tester) async {
    setViewport(tester, const Size(390, 844));
    final repository = await pumpPage(tester);

    await tester.enterText(find.byType(TextFormField), 'reader@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(repository.forgotPasswordEmail, 'reader@example.com');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('We sent a password reset link to reader@example.com'), findsOneWidget);
    expect(find.text('Reset token'), findsNothing);
    expect(find.text('New password'), findsNothing);
  });

  testWidgets('reset link page submits URL token with new password', (tester) async {
    setViewport(tester, const Size(390, 844));
    final repository = await pumpPage(tester, resetToken: 'reset-token-123', isResetLink: true);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), ' NewSecureP@ss123 ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), ' NewSecureP@ss123 ');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(repository.resetToken, 'reset-token-123');
    expect(repository.resetPasswordValue, ' NewSecureP@ss123 ');
    expect(find.text('Password reset'), findsOneWidget);
  });

  testWidgets('reset link page shows invalid state without token', (tester) async {
    setViewport(tester, const Size(390, 844));
    await pumpPage(tester, isResetLink: true);

    expect(find.text('Invalid reset link'), findsOneWidget);
    expect(find.text('Request new link'), findsOneWidget);
    expect(find.text('Reset token'), findsNothing);
    expect(find.text('New password'), findsNothing);
  });
}
