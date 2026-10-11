import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/register_page.dart';
import 'package:papyrus/pages/welcome_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/auth/auth_branding.dart';
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

  for (final (size, scale) in [
    (const Size(384, 832), 1.0),
    (const Size(360, 640), 1.0),
    (const Size(360, 640), 1.5),
    (const Size(1200, 800), 1.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('welcome branding and actions fit $size at text scale $scale (dark: $dark)', (tester) async {
        setViewport(tester, size);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);

        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const WelcomePage(),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(AuthBranding), findsOneWidget);
        expect(find.text('Papyrus'), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (scale == 1.0) {
          final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
          expect(scrollable.position.maxScrollExtent, 0);
          final brandingPosition = tester.getTopLeft(find.byType(AuthBranding));
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byType(AuthBranding)), brandingPosition);
        }

        for (final label in ['Create an account', 'Sign in', 'Continue offline']) {
          final action = find.text(label);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      });
    }
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
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPadding);

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
    expect(tester.getCenter(branding).dy, moreOrLessEquals((24 + ComponentSizes.mobileHeroHeight - 30) / 2));
  });

  for (final register in [false, true]) {
    testWidgets('${register ? 'register' : 'login'} fits a phone viewport above system navigation', (tester) async {
      setViewport(tester, const Size(384, 832));
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: register ? const RegisterPage() : const LoginPage(),
        ),
      );

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final offlineButton = find.widgetWithText(TextButton, 'Continue offline');
      expect(scrollable.position.maxScrollExtent, 0);
      expect(tester.getRect(offlineButton).bottom, lessThanOrEqualTo(784));
      expect(offlineButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

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
