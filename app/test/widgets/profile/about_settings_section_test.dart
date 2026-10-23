import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launched = <String>[];

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Papyrus',
      packageName: 'papyrus',
      version: '2.3.4',
      buildNumber: '57',
      buildSignature: '',
    );
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        }

        return null;
      },
    );
  });

  for (final desktop in [false, true]) {
    testWidgets('About uses installed version and working destinations, desktop=$desktop', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: AboutSettingsSection(isDesktop: desktop)),
          ),
          GoRoute(
            path: '/profile/licenses',
            builder: (context, state) => const Scaffold(body: Text('License destination')),
          ),
          GoRoute(
            path: '/profile/support',
            builder: (context, state) => const Scaffold(body: Text('Support destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('2.3.4 (57)'), findsOneWidget);
      expect(find.text('1.0.0'), findsNothing);
      await tester.tap(find.text("What's new"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub repository'));
      await tester.pumpAndSettle();
      expect(launched, [
        'https://github.com/PapyrusReader/client/releases/tag/v2.3.4+57',
        'https://github.com/PapyrusReader/client',
      ]);
      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();
      expect(find.text('License destination'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(find.text('Support destination'), findsOneWidget);
    });
  }

  testWidgets('failed external link provides feedback', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => false,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AboutSettingsSection())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub repository'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open'), findsOneWidget);
  });
}
