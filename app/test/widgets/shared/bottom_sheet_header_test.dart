import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    testWidgets('compact header keeps its 48-pixel frame with ${theme.brightness} theme', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: BottomSheetHeader(title: 'New shelf'),
          ),
        ),
      );

      expect(tester.getSize(find.byType(BottomSheetHeader)).height, 48);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.getTopLeft(find.text('New shelf')).dx, 24);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop titles are larger without restoring the tall header', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: BottomSheetHeader(title: 'New shelf')),
      ),
    );

    final titleContext = tester.element(find.text('New shelf'));
    expect(DefaultTextStyle.of(titleContext).style.fontSize, 22);
    expect(tester.getSize(find.byType(BottomSheetHeader)).height, lessThan(56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long titles wrap and grow with accessibility text size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    const title = 'A very long sheet title that should remain fully readable';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: BottomSheetHeader(title: title)),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(title));
    expect(text.maxLines, isNull);
    expect(tester.getSize(find.byType(BottomSheetHeader)).height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers an accessible dismiss action without an extra button', (tester) async {
    final semantics = tester.ensureSemantics();
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomSheetHeader(title: 'Details', onDismiss: () => dismissed = true),
        ),
      ),
    );

    final dismiss = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.onDismiss != null);
    expect(dismiss, findsOneWidget);
    tester.widget<Semantics>(dismiss).properties.onDismiss!();
    expect(dismissed, isTrue);
    expect(find.byType(IconButton), findsNothing);
    semantics.dispose();
  });
}
