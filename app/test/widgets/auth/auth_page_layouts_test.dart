import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/register_page.dart';
import 'package:papyrus/pages/welcome_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/auth/auth_hero_panel.dart';
import 'package:papyrus/widgets/auth/auth_page_layouts.dart';

void main() {
  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final font = File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
    await (FontLoader('MadimiOne')..addFont(rootBundle.load('fonts/MadimiOne-Regular.ttf'))).load();
  });

  void setViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('welcome actions remain reachable with large text on a small screen', (tester) async {
    setViewport(tester, const Size(360, 640));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const WelcomePage(),
      ),
    );

    for (final label in ['Create an account', 'Sign in', 'Continue offline']) {
      final action = find.text(label);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  for (final register in [false, true]) {
    testWidgets('${register ? 'register' : 'login'} remains scrollable with large text and keyboard', (tester) async {
      setViewport(tester, const Size(360, 780));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: register ? const RegisterPage() : const LoginPage(),
        ),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      final offlineButton = find.widgetWithText(TextButton, 'Continue offline');
      expect(tester.getRect(offlineButton).bottom, lessThanOrEqualTo(480));
      expect(offlineButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('auth header collapses and scrolls away so the rest of the form is reachable', (tester) async {
    setViewport(tester, const Size(360, 500));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const RegisterPage()));
    final header = find.byType(CompactAuthHeader);
    final expandedSize = tester.getSize(header);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(expandedSize.height / 4);
    await tester.pump();
    expect(tester.getSize(header).height, lessThan(expandedSize.height));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(header.hitTestable(), findsNothing);
    expect(find.text('Continue offline').hitTestable(), findsOneWidget);
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(header), expandedSize);
    expect(tester.takeException(), isNull);
  });

  for (final motion in ['normal', 'reduced', 'eink']) {
    testWidgets('keyboard changes preserve login input and focus with $motion motion', (tester) async {
      setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        MaterialApp(
          theme: motion == 'eink' ? AppTheme.eink : AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: motion == 'reduced'),
            child: child!,
          ),
          home: const LoginPage(),
        ),
      );

      final header = find.byType(CompactAuthHeader);
      final expandedSize = tester.getSize(header);
      await tester.enterText(find.byType(TextFormField).first, 'reader@example.com');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      final firstKeyboardFrame = tester.getSize(header);
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, lessThan(expandedSize.height));

      if (motion != 'normal') {
        expect(tester.getSize(header), firstKeyboardFrame);
      }

      var email = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(email.controller.text, 'reader@example.com');
      expect(email.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(tester.getSize(header), expandedSize);
      email = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(email.controller.text, 'reader@example.com');
      expect(email.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

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
            footer: const [],
            bottomActions: [TextButton(onPressed: () => continued = true, child: const Text('Continue offline'))],
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
