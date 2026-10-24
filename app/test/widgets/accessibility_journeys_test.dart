import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/register_page.dart';
import 'package:papyrus/pages/forgot_password_page.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/app_accessibility.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book_details/book_action_buttons.dart';
import 'package:papyrus/widgets/input/email_input.dart';
import 'package:papyrus/widgets/input/name_input.dart';
import 'package:papyrus/widgets/input/password_input.dart';
import 'package:papyrus/widgets/input/search_field.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';
import 'package:papyrus/widgets/shell/mobile_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(AppTheme.dyslexiaFontFamily);

    for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      loader.addFont(rootBundle.load('fonts/OpenDyslexic/OpenDyslexic-$style.otf'));
    }

    await loader.load();
  });

  for (final (name, page) in [
    ('login', const LoginPage()),
    ('registration', const RegisterPage()),
    ('recovery', const ForgotPasswordPage()),
  ]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets('$name retains reachable fields and submission at $width with combined enlargement', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final preferences = PreferencesProvider(await SharedPreferences.getInstance())
          ..interfaceTextEnlargement = 2
          ..boldInterfaceText = true;
        addTearDown(preferences.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.withTypography(AppTheme.highContrastLight, dyslexiaFont: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: AppAccessibilityScope(preferences: preferences, child: child!),
            ),
            home: page,
          ),
        );
        await tester.pumpAndSettle();
        if (name == 'registration') {
          final displayName = find.descendant(of: find.byType(NameInput), matching: find.byType(TextFormField));
          await tester.ensureVisible(displayName);
          await tester.enterText(displayName, 'Reader');
        }

        final email = find.byType(EmailInput);
        await tester.ensureVisible(email);
        await tester.enterText(find.descendant(of: email, matching: find.byType(TextFormField)), 'invalid');
        await tester.pump();
        // Opening the keyboard must not trap the submit action below the viewport.
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
        final submit = find.byType(ElevatedButton).first;
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Not a valid email'), findsOneWidget);
        final field = tester.widget<EditableText>(find.descendant(of: email, matching: find.byType(EditableText)));
        expect(field.controller.text, 'invalid');
        expect(field.focusNode.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('email and password support autofill, paste, and labeled visibility controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: AutofillGroup(
            child: Column(
              children: [
                EmailInput(labelText: 'Email'),
                PasswordInput(labelText: 'Password'),
              ],
            ),
          ),
        ),
      ),
    );
    final password = find.descendant(of: find.byType(PasswordInput), matching: find.byType(EditableText));
    final field = tester.widget<EditableText>(password);
    expect(field.autofillHints, contains(AutofillHints.password));
    expect(tester.widget<EditableText>(find.byType(EditableText).first).autofillHints, contains(AutofillHints.email));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': 'pasted-password'};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.enterText(password, '');
    await tester.pump();
    await tester.runAsync(() async {
      await Clipboard.setData(const ClipboardData(text: 'pasted-password'));
      await tester.state<EditableTextState>(password).pasteText(SelectionChangedCause.keyboard);
    });
    await tester.pump();
    expect(field.controller.text, 'pasted-password');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<EditableText>(password).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('eink', AppTheme.eink),
    ('high contrast light', AppTheme.highContrastLight),
    ('high contrast dark', AppTheme.highContrastDark),
  ]) {
    testWidgets('$name book actions and search pass label, touch-target and text contrast checks', (tester) async {
      final semantics = tester.ensureSemantics();
      final search = TextEditingController(text: 'Book');
      addTearDown(search.dispose);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  BookActionButtons(
                    book: Book(id: 'book', title: 'Book', author: 'Author', addedAt: DateTime(2026)),
                    onContinueReading: () {},
                    onEdit: () {},
                    onToggleFavorite: () {},
                  ),
                  SearchField(controller: search, hintText: 'Search books'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Edit book'), findsOneWidget);
        expect(find.byTooltip('Add to favorites'), findsOneWidget);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('large-text navigation reaches Settings without clamping text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 720), textScaler: TextScaler.linear(4)),
          child: Scaffold(
            bottomNavigationBar: MobileBottomNav(
              currentPath: '/library/books',
              items: const [
                AppShellNavItem(path: '/library', label: 'Library', icon: Icons.book),
                AppShellNavItem(path: '/statistics', label: 'Statistics', icon: Icons.bar_chart),
                AppShellNavItem(path: '/profile', label: 'Settings', icon: Icons.settings),
              ],
              onNavigate: (value) => destination = value,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(destination, '/profile');
    expect(MediaQuery.textScalerOf(tester.element(find.text('Settings'))).scale(14), 56);
    expect(tester.takeException(), isNull);
  });
}
