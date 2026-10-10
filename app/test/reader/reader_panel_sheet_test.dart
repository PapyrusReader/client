import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/reader/reader_panel_sheet.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

void main() {
  for (final eink in [false, true]) {
    testWidgets('host reader sheet expands, scrolls and dismisses (eink: $eink)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      final theme = eink ? AppTheme.eink : AppTheme.dark;
      late ModalBottomSheetRoute<void> route;
      ScrollController? contentController;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  route =
                      buildReaderPanelSheet(
                            context,
                            ReaderPanelRouteContext(
                              kind: ReaderPanelKind.tableOfContents,
                              title: 'Contents',
                              buildContent: (context, controller) {
                                contentController = controller;

                                return ListView(
                                  controller: controller,
                                  shrinkWrap: true,
                                  children: [
                                    for (var chapter = 0; chapter < 80; chapter++)
                                      ListTile(title: Text('Chapter $chapter')),
                                  ],
                                );
                              },
                            ),
                          )
                          as ModalBottomSheetRoute<void>;

                  Navigator.of(context).push(route);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheet), findsOneWidget);
      expect(find.byType(BottomSheetHeader), findsOneWidget);
      expect(find.byType(ExpandableBottomSheet), findsOneWidget);
      expect(contentController, isNotNull);
      expect(contentController!.offset, 0);
      expect(Theme.of(tester.element(find.byType(AppBottomSheet))).brightness, theme.brightness);

      if (eink) {
        expect(route.transitionDuration, Duration.zero);
        expect(route.shape, theme.bottomSheetTheme.shape);
      }

      final initialTop = tester.getTopLeft(find.byType(BottomSheetHeader)).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(BottomSheetHeader)).dy, lessThan(initialTop));
      expect(contentController!.offset, 0);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(contentController!.offset, greaterThan(0));
      await tester.fling(find.byType(BottomSheetHeader), const Offset(0, 700), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheet), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short PDF-style panels fit their content at large text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                buildReaderPanelSheet(
                  context,
                  ReaderPanelRouteContext(
                    kind: ReaderPanelKind.settings,
                    title: 'Reading settings',
                    buildContent: (context, controller) => ListView(
                      controller: controller,
                      shrinkWrap: true,
                      children: const [ListTile(title: Text('Reading mode'))],
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBottomSheet)).height, lessThan(400));
    expect(find.text('Reading settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
