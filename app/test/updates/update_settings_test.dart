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
