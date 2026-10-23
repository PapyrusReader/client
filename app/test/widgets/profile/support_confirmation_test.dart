import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/services/support_api_client.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/profile/support_confirmation.dart';

void main() {
  final issue = SupportIssue(number: 74, url: Uri.parse('https://github.com/PapyrusReader/client/issues/74'));

  for (final theme in {'dark': AppTheme.dark, 'light': AppTheme.light, 'eink': AppTheme.eink}.entries) {
    for (final compact in [false, true]) {
      testWidgets('confirmation link is reachable in ${theme.key}, compact=$compact', (tester) async {
        tester.view.physicalSize = Size(compact ? 320 : 900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? launched;
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') {
            launched = (call.arguments as Map)['url'] as String;
            return true;
          }

          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SupportConfirmation(issue: issue),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('#74'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('View issue'));
        await tester.tap(find.text('View issue'));
        await tester.pumpAndSettle();
        expect(launched, issue.url.toString());
        expect(tester.takeException(), isNull);
      });
    }
  }
}
