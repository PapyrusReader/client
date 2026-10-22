import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/developer_options_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final width in [400.0, 1200.0]) {
      testWidgets('settings back navigation works at $width in ${theme.brightness}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        addTearDown(tester.view.reset);
        final navigator = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppPageBar(context: context, title: const Text('Root')),
              ),
            ),
          ),
        );

        expect(find.byType(BackButton), findsNothing);
        navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const DeveloperOptionsPage()));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
        expect(tester.getSize(find.byType(AppBar)).height, width == 400 ? 80 : kToolbarHeight);

        if (width == 400) {
          expect(tester.getCenter(find.byType(BackButtonIcon)), const Offset(40, 40));
        }

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Root'), findsOneWidget);
        expect(find.text('Developer options'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('full screen routes retain automatic close and custom colors', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Root')),
      ),
    );

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppPageBar(
            context: context,
            title: const Text('Scan ISBN'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, Colors.black);
    expect(bar.iconTheme!.color, Colors.white);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
  });
}
