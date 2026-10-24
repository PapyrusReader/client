import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/pages/profile_page.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/acquisition_availability_provider.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/widgets/profile/profile_menu_item.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements RefreshTokenStorage {
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String val) async => token = val;
}

class _MockAuthRepo extends AuthRepository {
  _MockAuthRepo()
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'))),
        tokenStore: TokenStore(_MemoryStorage()),
      );

  @override
  Future<AuthTokens?> bootstrap() async => AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: '11111111-1111-1111-1111-111111111111',
      email: 'reader@example.com',
      displayName: 'Reader Profile',
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
    ),
  );
}

class _OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

class _MockPowerSyncService extends PapyrusPowerSyncService {
  _MockPowerSyncService() : super(connectorFactory: _OfflineConnector.new, connectAuthenticated: false);

  @override
  LibraryDatabaseMode? get mode => LibraryDatabaseMode.guest;

  @override
  SyncState get syncState => const SyncState(connected: true, connecting: false, downloading: false, uploading: false);

  @override
  Stream<SyncState> get syncStates => Stream.value(syncState);
}

void main() {
  group('ProfilePage Full Integration', () {
    late SharedPreferences prefs;
    late AuthProvider authProvider;
    late _MockPowerSyncService powerSync;
    late SyncSettingsProvider syncSettings;
    late DataStore dataStore;
    late MediaUploadQueue uploadQueue;
    late PreferencesProvider prefsProvider;
    late AcquisitionAvailabilityProvider availabilityProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      authProvider = AuthProvider(prefs, repository: _MockAuthRepo(), bootstrapOnCreate: false);
      await authProvider.bootstrap();
      powerSync = _MockPowerSyncService();

      syncSettings = SyncSettingsProvider(
        prefs,
        officialConfig: PapyrusApiConfig(
          serverBaseUri: Uri.parse('https://api.test'),
          powerSyncServiceUri: Uri.parse('https://data-sync.test'),
        ),
      );

      dataStore = DataStore();
      uploadQueue = MediaUploadQueue(prefs);
      prefsProvider = PreferencesProvider(prefs);
      availabilityProvider = AcquisitionAvailabilityProvider(authProvider: authProvider);
    });

    Widget buildApp({required Size screenSize, TextScaler textScaler = TextScaler.noScaling}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          Provider<PapyrusPowerSyncService>.value(value: powerSync),
          ChangeNotifierProvider<SyncSettingsProvider>.value(value: syncSettings),
          StreamProvider<SyncState>.value(value: powerSync.syncStates, initialData: powerSync.syncState),
          ChangeNotifierProvider<DataStore>.value(value: dataStore),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: uploadQueue),
          ChangeNotifierProvider<PreferencesProvider>.value(value: prefsProvider),
          ChangeNotifierProvider<AcquisitionAvailabilityProvider>.value(value: availabilityProvider),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: screenSize, textScaler: textScaler),
            child: const ProfilePage(),
          ),
        ),
      );
    }

    testWidgets('mobile layout renders all sections and displays logout dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(screenSize: const Size(400, 900)));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Reader Profile'), findsOneWidget);
      expect(find.text('reader@example.com'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Change password'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Appearance'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Default font'), findsNothing);
      expect(find.text('Default view'), findsNothing);
      expect(find.text('Developer options'), findsNothing);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Notifications'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Goal reminders'), findsOneWidget);
      final reminders = find.widgetWithText(SettingsToggleRow, 'Goal reminders');
      final remindersValue = prefsProvider.goalReminders;
      expect(tester.widget<SettingsToggleRow>(reminders).onChanged, isNull);
      await tester.tap(reminders);
      expect(prefsProvider.goalReminders, remindersValue);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Storage'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Clear local library'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Privacy & data'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Analytics'), findsOneWidget);
      final analytics = find.widgetWithText(SettingsToggleRow, 'Analytics');
      final analyticsValue = prefsProvider.analyticsOptIn;
      expect(tester.widget<SettingsToggleRow>(analytics).onChanged, isNull);
      await tester.tap(analytics);
      expect(prefsProvider.analyticsOptIn, analyticsValue);

      for (final label in ['Privacy policy', 'Export all data', 'Import data', 'Clear local data']) {
        final row = tester.widget<SettingsRow>(find.widgetWithText(SettingsRow, label));
        expect(row.enabled, isFalse);
        expect(row.onTap, isNull);
      }
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'Accessibility'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reduce animations'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsSectionHeader, 'About'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Version'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(ProfileMenuItem, 'Log out'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ProfileMenuItem, 'Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to log out?'), findsNothing);
    });

    testWidgets('desktop settings scrolls when the pointer is over empty space beside the form', (tester) async {
      const screenSize = Size(1280, 600);
      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(screenSize: screenSize));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextFormField, 'Display name');
      final initialTop = tester.getTopLeft(name).dy;
      const pointerPosition = Offset(1240, 300);
      expect(pointerPosition.dx, greaterThan(tester.getTopRight(name).dx));
      await tester.sendEventToBinding(
        const PointerScrollEvent(position: pointerPosition, scrollDelta: Offset(0, 200)),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(name).dy, lessThan(initialTop));
      expect(tester.takeException(), isNull);
    });

    testWidgets('short desktop settings sections stay at the top of the content pane', (tester) async {
      const screenSize = Size(1280, 900);
      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(screenSize: screenSize));
      await tester.pumpAndSettle();
      final initialHeadingTop = tester.getTopLeft(find.text('Account').last).dy;
      await tester.tap(find.widgetWithText(InkWell, 'About'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('About').last).dy, initialHeadingTop);
      expect(tester.takeException(), isNull);
    });

    for (final textScale in [1.0, 2.0]) {
      testWidgets('desktop settings keeps keyboard traversal within each column at ${textScale}x text', (tester) async {
        const screenSize = Size(1280, 900);
        await tester.binding.setSurfaceSize(screenSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(buildApp(screenSize: screenSize, textScaler: TextScaler.linear(textScale)));
        await tester.pumpAndSettle();
        final accessibility = find.widgetWithText(InkWell, 'Accessibility');
        await tester.ensureVisible(accessibility);
        await tester.tap(accessibility);
        await tester.pumpAndSettle();

        final labels = [
          'Account',
          'Appearance',
          'Storage',
          'Accessibility',
          'About',
          'Log out',
          'Interface text enlargement',
          'Interface font',
          'Increase contrast',
          'Bold interface text',
          'Reduce animations',
        ];

        FocusNode focusFor(String label) => Focus.of(tester.element(find.text(label).first));

        focusFor(labels.first).requestFocus();
        await tester.pumpAndSettle();

        for (final label in labels) {
          expect(focusFor(label).hasPrimaryFocus, isTrue, reason: 'Forward traversal should focus $label');

          if (label != labels.last) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
        }

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

        for (final label in labels.reversed.skip(1)) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(focusFor(label).hasPrimaryFocus, isTrue, reason: 'Reverse traversal should focus $label');
        }

        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
    }

    testWidgets('desktop layout navigates across all sections correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(screenSize: const Size(1200, 900)));
      await tester.pumpAndSettle();

      // Account section default
      expect(find.text('Account'), findsWidgets);
      expect(find.text('Reader Profile'), findsOneWidget);
      expect(find.text('Edit profile'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Display name'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

      // Navigate to Appearance
      await tester.tap(find.widgetWithText(InkWell, 'Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('System default'), findsOneWidget);

      for (final label in ['Reading', 'Library', 'Developer options']) {
        expect(find.text(label), findsNothing);
      }

      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpAndSettle();

        for (final label in ['Notifications', 'Privacy']) {
          final item = find.widgetWithText(InkWell, label);
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(node.flagsCollection.isEnabled, Tristate.isFalse);
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(find.text('System default'), findsOneWidget);
        }
      } finally {
        semantics.dispose();
      }

      // Navigate to Storage
      await tester.tap(find.widgetWithText(InkWell, 'Storage'));
      await tester.pumpAndSettle();
      expect(find.text('Library storage'), findsOneWidget);

      // Navigate to Accessibility
      await tester.tap(find.widgetWithText(InkWell, 'Accessibility'));
      await tester.pumpAndSettle();
      expect(find.text('Reduce animations'), findsOneWidget);

      // Navigate to About
      await tester.tap(find.widgetWithText(InkWell, 'About'));
      await tester.pumpAndSettle();
      expect(find.text('Version'), findsOneWidget);
      expect(find.text('Licenses'), findsOneWidget);

      // Trigger Logout dialog on desktop
      await tester.tap(find.widgetWithText(InkWell, 'Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to log out?'), findsNothing);
    });
  });
}
