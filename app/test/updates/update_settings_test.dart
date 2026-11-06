import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/pages/app_updates_page.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/updates/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final eink in [false, true]) {
    testWidgets('automatic toggle has no pressed ink and Back releases the settings guard, eink=$eink', (tester) async {
      SharedPreferences.setMockInitialValues({'updates.automatic': false});
      var checks = 0;
      final preferences = await SharedPreferences.getInstance();
      final updates = UpdateController(
        preferences: preferences,
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
        channelProvider: () async {
          checks++;
          return UpdateChannel.windows;
        },
      );

      addTearDown(updates.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: eink ? AppTheme.eink : AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showUpdateSettings(context, updates),
                  child: const Text('Open updates'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open updates'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final route = ModalRoute.of(tester.element(find.byType(AppUpdatesPage)))! as TransitionRoute<dynamic>;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(find.text('0.2.0 (6)'), findsOneWidget);
      expect(find.text('Not checked yet'), findsOneWidget);
      expect(updates.viewingSettings, isTrue);
      final label = tester.getTopLeft(find.text('Check automatically'));
      final before = await capture(tester, boundaryKey);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(Switch)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(await capture(tester, boundaryKey), before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(preferences.getBool('updates.automatic'), isTrue);
      expect(tester.getTopLeft(find.text('Check automatically')), label);
      expect(checks, 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open updates'), findsOneWidget);
      expect(updates.viewingSettings, isFalse);
    });
  }

  for (final (width, scale, eink) in [
    (1280.0, 1.0, false),
    (360.0, 1.0, false),
    (320.0, 2.0, false),
    (360.0, 2.0, true),
  ]) {
    testWidgets('check, failure, retry and success stay usable at width $width, scale $scale, eink=$eink', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      var result = Completer<int?>();
      final updates = UpdateController(
        preferences: await SharedPreferences.getInstance(),
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
        channelProvider: () async => UpdateChannel.play,
        playCheck: () => result.future,
      );

      addTearDown(updates.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: eink ? AppTheme.eink : AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: AppUpdatesPage(controller: updates),
        ),
      );

      await tester.pumpAndSettle();
      final checkButton = find.byKey(const ValueKey('check-updates'));

      for (final fails in [true, false]) {
        await tester.ensureVisible(checkButton);
        final buttonBounds = tester.getRect(checkButton);
        final buttonOffset = buttonBounds.top - tester.getTopLeft(find.text('Installed version')).dy;
        final toggleBounds = tester.getRect(find.byType(Switch));
        final previousStatus = fails ? 'Not checked yet' : 'Couldn’t check for updates';
        await tester.tap(checkButton);
        await tester.pump();
        expect(find.text(previousStatus), findsOneWidget);
        expect(find.byType(AppLinearProgressIndicator), findsNothing);
        expect(tester.widget<FilledButton>(checkButton).onPressed, isNull);
        expect(tester.getRect(checkButton), buttonBounds);
        expect(tester.getRect(find.byType(Switch)), toggleBounds);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Checking…'), findsOneWidget);
        expect(find.text(previousStatus), findsOneWidget);
        expect(find.byType(AppLinearProgressIndicator), findsOneWidget);
        expect(tester.getRect(checkButton), buttonBounds);
        expect(tester.getRect(find.byType(Switch)), toggleBounds);
        expect(tester.takeException(), isNull);

        if (fails) {
          result.completeError(StateError('Offline'));
        } else {
          result.complete(null);
        }

        await tester.pumpAndSettle();
        expect(find.text(fails ? 'Couldn’t check for updates' : 'You’re up to date'), findsOneWidget);
        expect(find.text(fails ? 'Retry' : 'Check for updates'), findsOneWidget);
        expect(find.textContaining('Last checked'), fails ? findsNothing : findsOneWidget);
        expect(tester.widget<FilledButton>(checkButton).onPressed, isNotNull);
        final action = tester.element(find.text(fails ? 'Retry' : 'Check for updates'));
        expect(DefaultTextStyle.of(action).style.color, Theme.of(action).colorScheme.onPrimary);
        expect(tester.takeException(), isNull);
        result = Completer<int?>();

        if (fails) {
          expect(
            tester.getRect(checkButton).top - tester.getTopLeft(find.text('Installed version')).dy,
            buttonOffset,
          );

          await tester.ensureVisible(checkButton);
          final retryBounds = tester.getRect(checkButton);
          final retryToggleBounds = tester.getRect(find.byType(Switch));
          await tester.tap(checkButton);
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Retry'), findsOneWidget);
          expect(find.text('Couldn’t check for updates'), findsOneWidget);
          expect(find.text('Please try again.'), findsNothing);
          expect(find.byType(AppLinearProgressIndicator), findsNothing);
          expect(tester.getRect(checkButton), retryBounds);
          expect(tester.getRect(find.byType(Switch)), retryToggleBounds);
          final retry = tester.element(find.text('Retry'));
          expect(DefaultTextStyle.of(retry).style.color, Theme.of(retry).colorScheme.onPrimary);
          result.completeError(StateError('Still offline'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(AppLinearProgressIndicator), findsNothing);
          expect(find.text('Retry'), findsOneWidget);
          expect(tester.getRect(checkButton), retryBounds);
          expect(tester.getRect(find.byType(Switch)), retryToggleBounds);
          result = Completer<int?>();
        }
      }
    });
  }

  testWidgets('download progress, retry and staged guidance preserve the automatic setting', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var attempt = 0;
    final download = Completer<String>();
    final updates = UpdateController(
      preferences: await SharedPreferences.getInstance(),
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.windows,
      manifest: () async => {
        'tag': 'v0.3.0+7',
        'version': '0.3.0',
        'build_number': 7,
        'assets': {
          'installer': {'name': 'papyrus-v0.3.0+7-windows-x64-setup.exe', 'sha256': 'a' * 64},
        },
      },
      installer: (_, progress) async {
        if (attempt++ == 0) {
          throw StateError('Disk full');
        }

        progress(0.5);
        return download.future;
      },
    );

    addTearDown(updates.dispose);
    await updates.check();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        home: AppUpdatesPage(controller: updates),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version 0.3.0 (7) is available'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t finish the update'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Downloading update: 50%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    download.complete('Close Papyrus to update');
    await tester.pumpAndSettle();
    expect(find.text('Ready to finish updating'), findsOneWidget);
    expect(find.text('Close Papyrus to update'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Check automatically'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (channel, label) in [
    (UpdateChannel.web, 'Reload'),
    (UpdateChannel.apt, 'Repository setup'),
    (UpdateChannel.manual, 'Downloads'),
  ]) {
    testWidgets('$channel offers the correct platform action', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final updates = UpdateController(
        preferences: await SharedPreferences.getInstance(),
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
        channelProvider: () async => channel,
        manifest: () async => {'tag': 'v0.3.0+7', 'version': '0.3.0', 'build_number': 7},
      );

      addTearDown(updates.dispose);
      await updates.check();
      await tester.pumpWidget(MaterialApp(home: AppUpdatesPage(controller: updates)));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, label), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    });
  }

  testWidgets('Back during a check allows reopening without losing the result', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = Completer<int?>();
    final updates = UpdateController(
      preferences: await SharedPreferences.getInstance(),
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
      channelProvider: () async => UpdateChannel.play,
      playCheck: () => result.future,
    );

    addTearDown(updates.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUpdateSettings(context, updates),
              child: const Text('Open updates'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(updates.viewingSettings, isFalse);
    result.complete(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open updates'));
    await tester.pumpAndSettle();
    expect(find.text('You’re up to date'), findsOneWidget);
    expect(find.textContaining('Last checked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('notice and dialog work on a narrow e-ink screen at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      var installs = 0;
      final updates = UpdateController(
        preferences: await SharedPreferences.getInstance(),
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
        channelProvider: () async => UpdateChannel.play,
        playCheck: () async => 7,
        installer: (_, _) async {
          installs++;
          return 'Follow Google Play to finish the update.';
        },
      );
      addTearDown(updates.dispose);
      final router = GoRouter(
        initialLocation: '/library/read/book',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Library')),
          ),
          GoRoute(
            path: '/library/read/book',
            builder: (_, _) => const Scaffold(body: Text('Reader')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: scale == 2 ? AppTheme.eink : AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: UpdateNotice(controller: updates, router: router, child: child!),
          ),
        ),
      );
      await updates.check();
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
      router.go('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(find.text('App update'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Check automatically'), findsNothing);
      expect(find.text('Check now'), findsNothing);
      expect(updates.automatic, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(installs, 1);
      expect(find.text('Follow Google Play to finish the update.'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
    });
  }
}

Future<List<int>> capture(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();

    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}
