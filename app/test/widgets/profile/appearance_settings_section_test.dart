import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/profile/appearance_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppearanceSettingsSection', () {
    late PreferencesProvider prefsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();
      prefsProvider = PreferencesProvider(prefs);
    });

    Widget buildSection({bool isDesktop = false}) {
      return ChangeNotifierProvider<PreferencesProvider>.value(
        value: prefsProvider,
        child: MaterialApp(
          home: Scaffold(body: AppearanceSettingsSection(isDesktop: isDesktop)),
        ),
      );
    }

    testWidgets('renders mobile appearance settings and opens theme picker', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: false));

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('E-ink'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(prefsProvider.themeModePref, equals('dark'));
    });

    testWidgets('renders desktop radio tile group and updates theme preference', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: true));

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('E-ink'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(prefsProvider.themeModePref, equals('dark'));
    });
  });
}
