import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/main.dart' as app;
import 'package:papyrus/pages/profile_page.dart';
import 'package:papyrus/pages/licenses_page.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile settings groups, saved preferences, and native Back', (tester) async {
    SharedPreferences.setMockInitialValues({'offline_mode': true, 'theme_mode': 'light'});
    await app.main();
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/profile');
    await tester.pumpAndSettle();
    final preferences = tester.element(find.byType(ProfilePage)).read<PreferencesProvider>();
    await binding.takeScreenshot('settings-index-light');

    for (final (title, control) in [
      ('Account', 'Display name'),
      ('Appearance', 'Theme'),
      ('Storage', 'Clear local library'),
      ('Accessibility', 'Reduce animations'),
      ('About', 'Version'),
    ]) {
      await tester.ensureVisible(find.widgetWithText(ListTile, title));
      await tester.tap(find.widgetWithText(ListTile, title));
      await tester.pumpAndSettle();
      expect(find.text(control), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.byType(ProfilePage).last))! as TransitionRoute<dynamic>;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      await binding.takeScreenshot('settings-${title.toLowerCase()}-light');

      if (title == 'About') {
        await tester.tap(find.widgetWithText(SettingsRow, 'Licenses'));

        for (var frame = 0; frame < 300; frame++) {
          await tester.pump(const Duration(milliseconds: 16));

          if (find.byType(LicensesPage).evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.byType(LicensesPage), findsOneWidget);
        expect(find.byType(ListTile), findsWidgets);
        expect(find.text('Loading licenses…'), findsNothing);
        await binding.takeScreenshot('settings-licenses-first-frame');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Version'), findsOneWidget);
      }

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/profile');
    }

    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(preferences.themeModePref, 'dark');
    await binding.takeScreenshot('settings-appearance-dark');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('Dark theme, page layout'), findsOneWidget);
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings-index-dark');
    preferences.interfaceTextEnlargement = 2;
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings-index-large-text');
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Accessibility'));
    await tester.tap(find.widgetWithText(ListTile, 'Accessibility'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings-accessibility-large-text');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    preferences.interfaceTextEnlargement = 1;
    preferences.reduceAnimations = true;
    await tester.pumpAndSettle();
    router.go('/profile/appearance');
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(ProfilePage).last))! as TransitionRoute<dynamic>;
    expect(route.transitionDuration, Duration.zero);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    preferences.reduceAnimations = false;
    preferences.themeModePref = 'eink';
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings-index-eink');
    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await tester.pump();
    expect(find.text('Theme'), findsOneWidget);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings-appearance-eink');
    expect(tester.takeException(), isNull);
  });
}
