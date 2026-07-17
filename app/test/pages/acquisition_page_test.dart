import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:papyrus/acquisition/acquisition_api_client.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/pages/acquisition_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRefreshTokenStorage implements RefreshTokenStorage {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String refreshToken) async {}
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: AuthApiClient(config: _config),
        tokenStore: TokenStore(_MemoryRefreshTokenStorage()),
      );

  @override
  Future<AuthTokens?> bootstrap() async => _tokens();

  @override
  Future<T> withFreshAccessToken<T>(Future<T> Function(String accessToken) action) {
    return action('access-token');
  }
}

class _FakeAcquisitionApiClient extends AcquisitionApiClient {
  _FakeAcquisitionApiClient() : super(config: _config, httpClient: MockClient((_) async => throw UnimplementedError()));

  final capabilitiesResult = const AcquisitionCapabilities(
    enabled: true,
    endpointKinds: [
      AcquisitionEndpointKind.prowlarr,
      AcquisitionEndpointKind.qbittorrent,
      AcquisitionEndpointKind.deluge,
    ],
    indexerKinds: [AcquisitionEndpointKind.prowlarr],
    downloadClientKinds: [AcquisitionEndpointKind.qbittorrent, AcquisitionEndpointKind.deluge],
    arrKinds: [],
    arrCommands: {},
  );
  Completer<void>? connectionTestCompleter;
  int connectionTestCalls = 0;

  @override
  Future<AcquisitionCapabilities> capabilities(String accessToken) async {
    return capabilitiesResult;
  }

  @override
  Future<List<AcquisitionEndpoint>> listEndpoints(String accessToken) async {
    return [];
  }

  @override
  Future<void> testEndpoint({
    required String accessToken,
    String? endpointId,
    AcquisitionEndpointKind? kind,
    Uri? baseUrl,
    String? apiKey,
    String? username,
    String? password,
  }) {
    connectionTestCalls += 1;
    return connectionTestCompleter?.future ?? Future<void>.value();
  }
}

final _config = PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'acquisition_enabled': true});
  });

  testWidgets('integration dialog shows credentials required by type', (tester) async {
    final apiClient = _FakeAcquisitionApiClient();
    await tester.pumpWidget(await _buildPage(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Integration'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'API key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<AcquisitionEndpointKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('qBittorrent').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'API key'), findsNothing);
    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<AcquisitionEndpointKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deluge').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'API key'), findsNothing);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('integration dialog locks actions and renders test errors', (tester) async {
    final apiClient = _FakeAcquisitionApiClient();
    final completer = Completer<void>();
    apiClient.connectionTestCompleter = completer;
    await tester.pumpWidget(await _buildPage(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Integration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Server URL'), 'http://prowlarr.local:9696');
    await tester.tap(find.byKey(const Key('acquisition-test-connection')));
    await tester.pump();

    expect(apiClient.connectionTestCalls, 1);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('acquisition-test-connection'))).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('acquisition-save'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('acquisition-test-connection')), warnIfMissed: false);
    await tester.pump();
    expect(apiClient.connectionTestCalls, 1);

    completer.completeError(const AuthApiException(statusCode: 502, message: 'Prowlarr connection test failed'));
    await tester.pumpAndSettle();

    expect(find.text('Prowlarr connection test failed'), findsOneWidget);
  });
}

Future<Widget> _buildPage(_FakeAcquisitionApiClient apiClient) async {
  final prefs = await SharedPreferences.getInstance();
  final authProvider = AuthProvider(prefs, repository: _FakeAuthRepository(), bootstrapOnCreate: false);
  await authProvider.bootstrap();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<PreferencesProvider>(create: (_) => PreferencesProvider(prefs)),
      ChangeNotifierProvider<SyncSettingsProvider>(create: (_) => SyncSettingsProvider(prefs, officialConfig: _config)),
    ],
    child: MaterialApp(home: AcquisitionPage(clientFactory: (_) => apiClient)),
  );
}

AuthTokens _tokens() {
  return AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: '11111111-1111-1111-1111-111111111111',
      email: 'reader@example.com',
      displayName: 'Reader',
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
    ),
  );
}
