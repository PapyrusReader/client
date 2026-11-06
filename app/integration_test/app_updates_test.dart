import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('update settings navigation and states on mobile', (tester) async {
    for (final (name, theme, scale) in [
      ('light', AppTheme.light, 1.0),
      ('dark', AppTheme.dark, 1.0),
      ('large-text', AppTheme.dark, 2.0),
      ('eink', AppTheme.eink, 1.0),
    ]) {
      SharedPreferences.setMockInitialValues({});
      var result = Completer<Map<String, dynamic>>();
      final installation = Completer<String>();
      final updates = UpdateController(
        preferences: await SharedPreferences.getInstance(),
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.3.0', buildNumber: '7'),
        channelProvider: () async => UpdateChannel.windows,
        manifest: () => result.future,
        installer: (_, progress) async {
          progress(0.5);
          return installation.future;
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: updates,
          child: MaterialApp(
            key: ValueKey(name),
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: SafeArea(child: AboutSettingsSection())),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('App updates'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Not checked yet'), findsOneWidget);
      await binding.takeScreenshot('updates-$name-unchecked');
      await tester.tap(find.text('Check automatically'));
      await tester.pumpAndSettle();
      expect(updates.automatic, isFalse);

      if (name == 'dark') {
        await tester.tap(find.text('Check for updates'));
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('updates-dark-checking');
        result.completeError(StateError('Offline'));
        await tester.pumpAndSettle();
        expect(find.text('Couldn’t check for updates'), findsOneWidget);
        await tester.pump(kThemeChangeDuration);
        await binding.takeScreenshot('updates-dark-error');
        final retryButton = find.byKey(const ValueKey('check-updates'));
        final retryBounds = tester.getRect(retryButton);
        final toggleBounds = tester.getRect(find.byType(Switch));
        result = Completer<Map<String, dynamic>>();
        await tester.tap(find.text('Retry'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Please try again.'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.getRect(retryButton), retryBounds);
        expect(tester.getRect(find.byType(Switch)), toggleBounds);
        result.completeError(StateError('Still offline'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.getRect(retryButton), retryBounds);
        await binding.takeScreenshot('updates-dark-quick-retry');
        result = Completer<Map<String, dynamic>>();
        await tester.tap(find.text('Retry'));
        await tester.pump();
        result.complete(_release(7));
        await tester.pumpAndSettle();
        expect(find.text('You’re up to date'), findsOneWidget);
        await binding.takeScreenshot('updates-dark-current');
        result = Completer<Map<String, dynamic>>();
        await tester.tap(find.text('Check for updates'));
        await tester.pump();
        result.complete(_release(8));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('updates-dark-available');
        await tester.tap(find.text('Update'));
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('updates-dark-progress');
        installation.complete('Close Papyrus normally to install the update.');
        await tester.pumpAndSettle();
        await binding.takeScreenshot('updates-dark-staged');
      }

      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Version'), findsOneWidget);
      expect(updates.viewingSettings, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      updates.dispose();
    }
  });
}

Map<String, dynamic> _release(int build) => {
  'tag': 'v0.3.0+$build',
  'version': '0.3.0',
  'build_number': build,
  'assets': {
    'installer': {'name': 'papyrus-v0.3.0+$build-windows-x64-setup.exe', 'sha256': 'a' * 64},
  },
};
