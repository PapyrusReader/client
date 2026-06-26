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

class CapturingAuthRepository extends AuthRepository {
  CapturingAuthRepository()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('http://server.test'))),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

  String? loginPassword;
  String? registerPassword;

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
    required String clientType,
    String? deviceLabel,
  }) async {
    loginPassword = password;
    throw const AuthApiException(statusCode: 401, message: 'Incorrect email or password.');
  }

  @override
  Future<AuthTokens> register({
    required String email,
    required String password,
    required String displayName,
    required String clientType,
    String? deviceLabel,
  }) async {
    registerPassword = password;
    throw const AuthApiException(statusCode: 409, message: 'Registration failed.');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void setViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<CapturingAuthRepository> pumpAuthPage(WidgetTester tester, Widget page) async {
    final prefs = await SharedPreferences.getInstance();
    final repository = CapturingAuthRepository();
    final provider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => provider,
        child: MaterialApp(home: page),
      ),
    );

    return repository;
  }

  testWidgets('login submits password exactly as typed', (tester) async {
    setViewport(tester);
    final repository = await pumpAuthPage(tester, const LoginPage());

    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'reader@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), ' NewSecureP@ss123 ');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(repository.loginPassword, ' NewSecureP@ss123 ');
  });

  testWidgets('register submits password exactly as typed', (tester) async {
    setViewport(tester);
    final repository = await pumpAuthPage(tester, const RegisterPage());

    await tester.enterText(find.widgetWithText(TextFormField, 'Display name'), 'Reader');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'reader@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), ' NewSecureP@ss123 ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), ' NewSecureP@ss123 ');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(repository.registerPassword, ' NewSecureP@ss123 ');
  });
}
