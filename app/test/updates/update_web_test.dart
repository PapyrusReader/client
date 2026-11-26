@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_settings.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browser startup and About never offer a native update', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    final updates = UpdateController(
      preferences: await SharedPreferences.getInstance(),
      backgroundEnabled: true,
      manifest: () async {
        requests++;
        throw StateError('Web must not fetch releases');
      },
      installer: (_, _) async {
        requests++;
        return '';
      },
    );

    addTearDown(updates.dispose);
    updates.start();
    await updates.check();
    await updates.install();
    expect(updates.supported, isFalse);
    expect(requests, 0);
    // Even stale availability cannot render a banner on web.
    updates.available = true;
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
      ChangeNotifierProvider.value(
        value: updates,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App updates'), findsNothing);
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
  });
}
