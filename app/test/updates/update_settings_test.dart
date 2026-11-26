import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_dialog.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/updates/update_settings.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> release() => {
  'tag': 'v0.3.0+7',
  'version': '0.3.0',
  'build_number': 7,
  'assets': {
    'installer': {'name': 'papyrus-v0.3.0+7-windows-x64-setup.exe', 'sha256': 'a' * 64},
  },
};

void main() {
  late UpdateController updates;
  late SharedPreferences preferences;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    updates = UpdateController(
      preferences: preferences,
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.windows,
      manifest: () async => release(),
    );
    router = GoRouter(
      routes: [
        ShellRoute(
          builder: (_, _, child) => UpdateNotice(controller: updates, router: router, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                appBar: AppBar(title: const Text('Library')),
                body: TextButton(
                  onPressed: () => showUpdateSettings(context, updates),
                  child: const Text('Check for updates manually'),
                ),
              ),
            ),
            GoRoute(
              path: '/read/book',
              builder: (_, _) => const Scaffold(body: Text('Reader')),
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() {
    updates.dispose();
    router.dispose();
  });

  Future<void> mount(WidgetTester tester, {ThemeData? theme, double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: theme ?? AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final exit in ['Dismiss', 'Escape', 'barrier', 'back']) {
    testWidgets('$exit closes a modal in place and dismisses the session notice', (tester) async {
      await updates.check(notifyUser: true);
      await mount(tester);
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('View update'), findsOneWidget);
      expect(updates.showNotice, isTrue);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Version 0.3.0 (7) is available'), findsOneWidget);

      switch (exit) {
        case 'Escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'barrier':
          await tester.tapAt(Offset(5, tester.view.physicalSize.height / tester.view.devicePixelRatio - 5));
        case 'back':
          await tester.binding.handlePopRoute();
        default:
          await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')));
      }

      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('View update'), findsNothing);
      expect(updates.viewingSettings, isFalse);
      expect(updates.available, isTrue);
      await updates.check(notifyUser: true);
      await tester.pumpAndSettle();
      expect(find.text('View update'), findsNothing);
      await tester.tap(find.text('Check for updates manually'));
      await tester.pumpAndSettle();
      expect(find.text('Update'), findsOneWidget);
    });
  }

  testWidgets('banner consumes the top safe area only once', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.reset);
    await updates.check(notifyUser: true);
    await mount(tester);
    final banner = tester.getRect(find.byType(MaterialBanner));
    final appBar = tester.getRect(find.byType(AppBar));
    expect(banner.top, 24);
    expect(appBar.top, banner.bottom);
    expect(appBar.height, kToolbarHeight);
    final context = tester.element(find.byType(Scaffold));
    expect(MediaQuery.paddingOf(context), const EdgeInsets.only(bottom: 34));
    expect(MediaQuery.viewPaddingOf(context), const EdgeInsets.only(bottom: 34));
    await tester.tap(find.byKey(const ValueKey('dismiss-update-notice')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 24);
    expect(MediaQuery.paddingOf(context), const EdgeInsets.only(top: 24, bottom: 34));
  });

  testWidgets('root modal backdrop covers and blocks the banner', (tester) async {
    await updates.check(notifyUser: true);
    await mount(tester);
    final banner = tester.getRect(find.byType(MaterialBanner));
    final dismiss = tester.getCenter(find.byKey(const ValueKey('dismiss-update-notice')));
    final context = tester.element(find.text('Check for updates manually'));
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(title: Text('Another dialog')),
    );
    await tester.pumpAndSettle();
    final barrier = find.byType(ModalBarrier).last;
    final barrierBounds = tester.getRect(barrier);
    expect(barrierBounds.contains(banner.center), isTrue);
    expect(tester.widget<ModalBarrier>(barrier).color!.a, greaterThan(0));
    expect(find.byKey(const ValueKey('dismiss-update-notice')).hitTestable(), findsNothing);
    await tester.tapAt(dismiss);
    await tester.pumpAndSettle();
    expect(updates.showNotice, isTrue);
    expect(find.text('Another dialog'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog)), rootNavigator: true).pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(find.text('View update').hitTestable(), findsOneWidget);
  });

  testWidgets('banner close explicitly dismisses, while reading only hides it', (tester) async {
    await updates.check(notifyUser: true);
    await mount(tester);
    router.go('/read/book');
    await tester.pumpAndSettle();
    expect(find.text('View update'), findsNothing);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('View update'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismiss-update-notice')));
    await tester.pumpAndSettle();
    expect(find.text('View update'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(preferences.getInt('updates.skippedBuild'), isNull);
  });

  for (final (width, scale, theme) in [
    (1280.0, 1.0, AppTheme.light),
    (360.0, 1.0, AppTheme.dark),
    (320.0, 2.0, AppTheme.dark),
    (360.0, 2.0, AppTheme.eink),
  ]) {
    testWidgets('skip checkbox and modal actions fit $width at scale $scale', (tester) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await updates.check(notifyUser: true);
      await mount(tester, theme: theme, scale: scale);
      final noticeBounds = tester.getRect(find.byType(MaterialBanner));
      final titleBounds = tester.getRect(find.text('Update available'));
      final viewBounds = tester.getRect(find.text('View update'));
      final dismissBounds = tester.getRect(find.byKey(const ValueKey('dismiss-update-notice')));
      expect(titleBounds.center.dy, closeTo(viewBounds.center.dy, 1));
      expect(titleBounds.center.dy, closeTo(dismissBounds.center.dy, 1));
      expect(noticeBounds.height, lessThanOrEqualTo(60));
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(MaterialBanner)), noticeBounds);
      expect(updates.showNotice, isTrue);

      if (width >= 600 && scale == 1) {
        expect(tester.getSize(find.byKey(const ValueKey('skip-update-version'))).height, lessThanOrEqualTo(48));
        final version = tester.getRect(find.text('Version 0.3.0 (7) is available'));
        final skip = tester.getRect(find.byKey(const ValueKey('skip-update-version')));
        expect(skip.top - version.bottom, lessThanOrEqualTo(8));
      }

      final route = ModalRoute.of(tester.element(find.byType(UpdateDialog)))! as TransitionRoute<dynamic>;

      if (theme == AppTheme.eink) {
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
      }

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Skip this version'));
      await tester.tap(find.text('Skip this version'));
      await tester.pumpAndSettle();
      expect(preferences.getInt('updates.skippedBuild'), 7);
      expect(updates.showNotice, isTrue);
      expect(tester.getRect(find.byType(MaterialBanner)), noticeBounds);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      final updateBounds = tester.getRect(find.widgetWithText(FilledButton, 'Update'));
      expect(updateBounds.bottom, lessThanOrEqualTo(780));
      expect(updateBounds.right, lessThanOrEqualTo(width));

      if (width < 600) {
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')), findsNothing);
        final close = find.byKey(const ValueKey('close-update-dialog'));
        expect(tester.getRect(close).bottom, lessThan(updateBounds.top));
        await tester.tap(close);
      } else {
        expect(find.byKey(const ValueKey('close-update-dialog')), findsNothing);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')));
      }

      await tester.pumpAndSettle();
      expect(find.text('View update'), findsNothing);
      await tester.tap(find.text('Check for updates manually'));
      await tester.pumpAndSettle();
      expect(find.text('Update'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile up-to-date dialog has one footer action and a header close button', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await updates.initialize();
    updates.status = UpdateStatus.upToDate;
    await preferences.setInt('updates.lastCheck', DateTime(2026, 11, 24, 1, 20).millisecondsSinceEpoch);
    await mount(tester);
    await tester.tap(find.text('Check for updates manually'));
    await tester.pumpAndSettle();
    expect(find.text('You’re up to date'), findsOneWidget);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.actions, hasLength(1));
    expect(find.text('Dismiss'), findsNothing);
    final close = find.byKey(const ValueKey('close-update-dialog'));
    final action = find.widgetWithText(FilledButton, 'Check for updates');
    expect(tester.getRect(close).bottom, lessThan(tester.getRect(action).top));
    expect(tester.getRect(action).right, lessThanOrEqualTo(296));
    expect(tester.takeException(), isNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(updates.viewingSettings, isFalse);
  });

  testWidgets('manual check and retry refresh metadata without raising a banner or installing', (tester) async {
    var checks = 0;
    var installs = 0;
    updates.dispose();
    updates = UpdateController(
      preferences: preferences,
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.windows,
      manifest: () async {
        if (++checks == 2) {
          throw StateError('Offline');
        }

        return release();
      },
      installer: (_, _) async {
        installs++;
        return 'Installed';
      },
    );
    await mount(tester);
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.tap(find.text('Check for updates manually'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.3.0 (7) is available'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    await updates.check();
    await tester.pumpAndSettle();
    expect(updates.available, isTrue);
    expect(find.text('Couldn’t check for updates'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(checks, 3);
    expect(installs, 0);
    expect(find.text('Version 0.3.0 (7) is available'), findsOneWidget);
    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('closing during a check keeps the result available in the modal', (tester) async {
    final result = Completer<Map<String, dynamic>>();
    updates.dispose();
    updates = UpdateController(
      preferences: preferences,
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.windows,
      manifest: () => result.future,
    );
    await mount(tester, theme: AppTheme.eink);
    await tester.tap(find.text('Check for updates manually'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check for updates'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')));
    await tester.pumpAndSettle();
    result.complete(release());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.tap(find.text('Check for updates manually'));
    await tester.pumpAndSettle();
    expect(find.text('Update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download progress, cancellation and retry remain in the modal', (tester) async {
    var attempt = 0;
    final installation = Completer<String>();
    updates.dispose();
    updates = UpdateController(
      preferences: preferences,
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.windows,
      manifest: () async => release(),
      installer: (_, progress) async {
        if (attempt++ == 0) {
          throw const UpdateInstallException('Update cancelled.');
        }

        progress(0.5);
        return installation.future;
      },
    );
    await updates.check(notifyUser: true);
    await mount(tester, theme: AppTheme.eink);
    await tester.tap(find.text('View update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Update cancelled.'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Downloading update: 50%'), findsOneWidget);
    expect(tester.widget<AppLinearProgressIndicator>(find.byType(AppLinearProgressIndicator)).value, 0.5);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(updates.busy, isTrue);
    await tester.tap(find.text('Check for updates manually'));
    await tester.pumpAndSettle();
    expect(find.text('Downloading update: 50%'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    installation.complete('Restart Papyrus to finish updating.');
    await tester.pumpAndSettle();
    expect(find.text('Restart Papyrus to finish updating.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
