@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_settings.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browser startup offers a deployed web release with an explicit Reload action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var reloads = 0;
    final updates = UpdateController(
      preferences: await SharedPreferences.getInstance(),
      appInfo: () async => PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.6.0', buildNumber: '10'),
      backgroundEnabled: true,
      manifest: () async => {'tag': 'v0.7.0+11', 'version': '0.7.0', 'build_number': 11},
      installer: (asset, _) async {
        expect(asset, isNull);
        reloads++;
        return 'Reloading Papyrus…';
      },
    );

    late final GoRouter router;
    router = GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) => UpdateNotice(controller: updates, router: router, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: AboutSettingsSection()),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => updates..start(),
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('View update'), findsOneWidget);
    expect(reloads, 0);
    await tester.tap(find.text('View update'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.7.0 (11) is available'), findsOneWidget);
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(reloads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
