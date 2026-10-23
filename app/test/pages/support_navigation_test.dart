import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/pages/support_page.dart';
import 'package:papyrus/providers/sidebar_provider.dart';
import 'package:papyrus/services/support_api_client.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../opds/catalog_store_test.dart' show MemorySecrets;

class _TrackingClient extends MockClient {
  _TrackingClient(super.handler);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});

    PackageInfo.setMockInitialValues(
      appName: 'Papyrus',
      packageName: 'papyrus',
      version: '0.0.4',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  for (final width in [390.0, 1280.0]) {
    for (final succeeds in [true, false]) {
      testWidgets('submission guards shell navigation at $width and releases after success=$succeeds', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final completion = Completer<http.Response>();
        final clients = <_TrackingClient>[];
        var submissions = 0;

        final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
          ..setScope('guest');

        addTearDown(catalogs.dispose);

        final router = GoRouter(
          initialLocation: '/profile/support',
          routes: [
            ShellRoute(
              builder: (_, _, child) => AdaptiveAppShell(child: child),
              routes: [
                GoRoute(path: '/dashboard', builder: (_, _) => const Text('Dashboard page')),
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => const Text('Profile page'),
                  routes: [
                    supportRoute(
                      createClient: () {
                        final client = _TrackingClient((_) {
                          submissions++;
                          return completion.future;
                        });

                        clients.add(client);

                        return SupportApiClient(
                          config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
                          httpClient: client,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

        addTearDown(router.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => DataStore()),
              ChangeNotifierProvider(create: (_) => SidebarProvider()),
              ChangeNotifierProvider.value(value: catalogs),
            ],
            child: MaterialApp.router(theme: AppTheme.eink, routerConfig: router),
          ),
        );

        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Reader issue');
        await tester.enterText(find.byType(TextFormField).last, 'The reader shows a blank page.');
        await tester.ensureVisible(find.text('Submit'));
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        final submittingPage = tester.state(find.byType(SupportPage));
        final submittingClient = clients.last;

        for (final destination in ['Dashboard', 'Profile']) {
          await tester.tap(find.text(destination));
          await tester.pumpAndSettle();
          expect(router.routerDelegate.currentConfiguration.uri.path, '/profile/support');
          expect(tester.state(find.byType(SupportPage)), same(submittingPage));
          expect(submittingClient.closed, isFalse);
        }

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(router.routerDelegate.currentConfiguration.uri.path, '/profile/support');
        expect(submittingClient.closed, isFalse);
        expect(submissions, 1);

        completion.complete(
          succeeds
              ? http.Response('{"number":42,"url":"https://github.com/PapyrusReader/client/issues/42"}', 201)
              : http.Response('', 503),
        );

        await tester.pumpAndSettle();

        if (succeeds) {
          expect(find.text('Thank you for helping us improve.'), findsOneWidget);
        } else {
          expect(find.text('Submission failed.'), findsOneWidget);
          expect(find.text('The reader shows a blank page.'), findsOneWidget);
        }

        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(find.text('Dashboard page'), findsOneWidget);
        expect(find.byType(SupportPage), findsNothing);
        expect(submittingClient.closed, isTrue);
        router.go('/profile/support');
        await tester.pumpAndSettle();
        expect(find.byType(SupportPage), findsOneWidget);
        expect(find.text('Submitting…'), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Profile page'), findsOneWidget);
        expect(clients.last.closed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
