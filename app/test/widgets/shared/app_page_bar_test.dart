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
        expect(tester.getSize(find.byType(AppBar)).height, width == 400 ? 64 : kToolbarHeight);

        if (width == 400) {
          expect(tester.getCenter(find.byType(BackButtonIcon)), const Offset(40, 32));
        }

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Root'), findsOneWidget);
        expect(find.text('Developer options'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    testWidgets('inline header matches app bar scrolling in ${theme.brightness} ${theme.appBarTheme.shape}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 850);
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final surfaces = <(Color?, double, Color?, Color?, ShapeBorder?)>[];

      for (final inline in [false, true]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                final body = ListView(
                  controller: scroll,
                  children: const [SizedBox(height: 2000)],
                );

                return Scaffold(
                  appBar: inline ? null : AppPageBar(context: context, title: const Text('Title')),
                  body: inline
                      ? Column(
                          children: [
                            const AppPageToolbar(content: Text('Title')),
                            Expanded(child: body),
                          ],
                        )
                      : body,
                );
              },
            ),
          ),
        );

        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        final surface = find
            .descendant(
              of: inline ? find.byType(AppPageToolbar) : find.byType(AppBar),
              matching: find.byType(Material),
            )
            .first;
        final before = tester.widget<Material>(surface);
        final bounds = tester.getRect(find.byType(AppPageToolbar));
        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        final after = tester.widget<Material>(surface);
        expect(after.elevation, theme.appBarTheme.scrolledUnderElevation);
        expect(tester.getRect(find.byType(AppPageToolbar)), bounds);
        surfaces.add((after.color, after.elevation, after.surfaceTintColor, after.shadowColor, after.shape));
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.widget<Material>(surface).elevation, before.elevation);
        expect(tester.takeException(), isNull);
      }

      expect(surfaces[1], surfaces[0]);
    });
  }

  testWidgets('inline header ignores horizontal and nested scrolling', (tester) async {
    final horizontal = ScrollController();
    final nested = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(nested.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              const AppPageToolbar(content: Text('Title')),
              SizedBox(
                height: 100,
                child: ListView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  children: const [SizedBox(width: 2000)],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    SizedBox(
                      height: 300,
                      child: ListView(controller: nested, children: const [SizedBox(height: 2000)]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final surface = find.descendant(of: find.byType(AppPageToolbar), matching: find.byType(Material)).first;
    horizontal.jumpTo(200);
    nested.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(surface).elevation, 0);
    expect(tester.takeException(), isNull);
  });

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
