import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/auth/auth_branding.dart';
import 'package:papyrus/widgets/auth/auth_page_layouts.dart';

void main() {
  void setViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('desktop auth layout shows branding over the hero image', (tester) async {
    setViewport(tester, const Size(1200, 800));

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopAuthLayout(
          heading: 'Heading',
          subtitle: 'Subtitle',
          form: const SizedBox.shrink(),
          footer: const [],
        ),
      ),
    );

    final branding = find.byType(AuthBranding);
    expect(find.text('Papyrus'), findsOneWidget);
    expect(branding, findsOneWidget);
    expect(tester.getTopLeft(branding).dx, Spacing.xl);
    expect(tester.getTopLeft(branding).dy, Spacing.xl);
  });

  testWidgets('mobile auth layout shows branding over the compact image header', (tester) async {
    setViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      MaterialApp(
        home: MobileAuthLayout(
          heading: 'Heading',
          subtitle: 'Subtitle',
          form: const SizedBox.shrink(),
          footer: const [],
        ),
      ),
    );

    final branding = find.byType(AuthBranding);
    expect(find.text('Papyrus'), findsOneWidget);
    expect(branding, findsOneWidget);
    expect(tester.getCenter(branding).dx, moreOrLessEquals(195));
    expect(tester.getTopLeft(branding).dy, Spacing.lg);
  });

  for (final keyboard in [false, true]) {
    testWidgets('mobile auth footer stays above ${keyboard ? 'the keyboard' : 'system navigation'}', (tester) async {
      setViewport(tester, const Size(390, 700));
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      tester.view.padding = FakeViewPadding(bottom: keyboard ? 0 : 48);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 300 : 0);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      var continued = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MobileAuthLayout(
            heading: 'Welcome back',
            subtitle: 'Sign in to continue',
            form: const SizedBox(height: 300),
            footer: [TextButton(onPressed: () => continued = true, child: const Text('Continue offline'))],
          ),
        ),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(TextButton, 'Continue offline');
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(keyboard ? 400 : 652));
      expect(tester.takeException(), isNull);
      await tester.tap(button);
      expect(continued, isTrue);
    });
  }

  testWidgets('desktop swap button is focused after form controls', (tester) async {
    setViewport(tester, const Size(1200, 800));
    final firstFocusNode = FocusNode(debugLabel: 'first');
    final secondFocusNode = FocusNode(debugLabel: 'second');
    final submitFocusNode = FocusNode(debugLabel: 'submit');
    final footerFocusNode = FocusNode(debugLabel: 'footer');

    addTearDown(() {
      firstFocusNode.dispose();
      secondFocusNode.dispose();
      submitFocusNode.dispose();
      footerFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopAuthLayout(
          heading: 'Heading',
          subtitle: 'Subtitle',
          form: Column(
            children: [
              TextField(focusNode: firstFocusNode),
              TextField(focusNode: secondFocusNode),
              ElevatedButton(focusNode: submitFocusNode, onPressed: () {}, child: const Text('Continue')),
            ],
          ),
          footer: [TextButton(focusNode: footerFocusNode, onPressed: () {}, child: const Text('Switch form'))],
        ),
      ),
    );

    firstFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(secondFocusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(submitFocusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(footerFocusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    expect(focusedContext, isNotNull);

    expect(
      find.descendant(of: find.byWidget(focusedContext!.widget), matching: find.byIcon(Icons.swap_horiz)),
      findsOneWidget,
    );
  });
}
