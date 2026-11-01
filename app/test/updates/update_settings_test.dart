import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/updates/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final eink in [false, true]) {
    testWidgets('automatic toggle stays aligned and has no pressed ink, eink=$eink', (tester) async {
      SharedPreferences.setMockInitialValues({'updates.automatic': false});
      var checks = 0;
      final preferences = await SharedPreferences.getInstance();
      final updates = UpdateController(
        preferences: preferences,
        channelProvider: () async {
          checks++;
          return UpdateChannel.windows;
        },
      );

      addTearDown(updates.dispose);
      const status = 'Could not check for updates. Check your connection and try again.';
      updates.message = status;
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
      final dialog = tester.getRect(find.byType(AlertDialog));
      final label = tester.getTopLeft(find.text('Check automatically'));
      expect(label.dx, tester.getTopLeft(find.text(status).hitTestable()).dx);
      final before = await capture(tester, boundaryKey);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(Switch)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(await capture(tester, boundaryKey), before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(preferences.getBool('updates.automatic'), isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text(status).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(AlertDialog)), dialog);
      expect(tester.getTopLeft(find.text('Check automatically')), label);
      expect(checks, 0);
      await tester.tap(find.text('Check automatically'));
      await tester.pumpAndSettle();
      expect(preferences.getBool('updates.automatic'), isFalse);
      expect(tester.getRect(find.byType(AlertDialog)), dialog);
      expect(checks, 0);
    });
  }

  for (final (width, scale, eink) in [(800.0, 1.0, false), (360.0, 1.0, false), (360.0, 2.0, true)]) {
    testWidgets('Check now keeps status and controls in place at width $width, scale $scale', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateSettings(context, updates),
                child: const Text('Open updates'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open updates'));
      await tester.pumpAndSettle();
      final dialog = tester.getRect(find.byType(AlertDialog));
      final toggle = tester.getRect(find.byType(Switch));
      final check = tester.getRect(find.widgetWithText(TextButton, 'Check now'));

      void expectStableLayout() {
        expect(tester.getRect(find.byType(AlertDialog)), dialog);
        expect(tester.getRect(find.byType(Switch)), toggle);
        expect(tester.getRect(find.widgetWithText(TextButton, 'Check now')), check);
        expect(tester.takeException(), isNull);
      }

      for (final fails in [true, false]) {
        await tester.tap(find.text('Check now'));
        await tester.pump();
        expect(find.text('Checking for updates…'), findsOneWidget);
        expectStableLayout();
        await tester.pump(const Duration(milliseconds: 200));
        expectStableLayout();

        if (fails) {
          result.completeError(StateError('Offline'));
        } else {
          result.complete(null);
        }

        await tester.pumpAndSettle();
        expect(
          find.text(fails ? UpdateController.checkFailureMessage : 'Papyrus is up to date.').hitTestable(),
          findsOneWidget,
        );
        expectStableLayout();
        result = Completer<int?>();
      }
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('notice and dialog work on a narrow e-ink screen at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final updates = UpdateController(
        preferences: await SharedPreferences.getInstance(),
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6'),
        channelProvider: () async => UpdateChannel.play,
        playCheck: () async => 7,
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
      expect(find.text('A Papyrus update is available.'), findsNothing);
      router.go('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(find.text('App updates'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      await tester.ensureVisible(find.text('Check automatically'));
      await tester.tap(find.text('Check automatically'));
      await tester.pumpAndSettle();
      expect(updates.automatic, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('A Papyrus update is available.'), findsNothing);
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
