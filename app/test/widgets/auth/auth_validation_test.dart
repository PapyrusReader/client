import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/forgot_password_page.dart';
import 'package:papyrus/pages/login_page.dart';
import 'package:papyrus/pages/register_page.dart';
import 'package:papyrus/widgets/input/email_input.dart';
import 'package:papyrus/widgets/input/password_input.dart';
import 'package:papyrus/widgets/input/validated_text_form_field.dart';

void main() {
  testWidgets('email errors wait for blur and clear when corrected', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final form = GlobalKey<FormState>();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: EmailInput(labelText: 'Email', controller: controller, focusNode: focus),
          ),
        ),
      ),
    );

    focus.requestFocus();
    await tester.pump();
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'reader@');
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsNothing);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'reader@example.com');
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'reader@');
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsNothing);
    expect(validateAndFocusForm(form.currentState!), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    controller.text = 'autofill@example.com';
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsNothing);
  });

  testWidgets('password confirmation waits for blur and clears when either password resolves the mismatch', (
    tester,
  ) async {
    final password = TextEditingController(text: 'first-password');
    final confirmation = TextEditingController();
    final confirmationFocus = FocusNode();
    addTearDown(password.dispose);
    addTearDown(confirmation.dispose);
    addTearDown(confirmationFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: Column(
              children: [
                PasswordInput(labelText: 'Password', controller: password),
                PasswordInput(
                  labelText: 'Confirm password',
                  controller: confirmation,
                  focusNode: confirmationFocus,
                  validationDependency: password,
                  extraValidator: (value) => value == password.text ? null : 'Passwords do not match',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final confirmationField = find.widgetWithText(TextFormField, 'Confirm password');
    await tester.enterText(confirmationField, 'second-password');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
    await tester.tap(find.descendant(of: confirmationField, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
    confirmationFocus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'second-password');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
    await tester.enterText(confirmationField, 'third-password');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
    confirmationFocus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    await tester.enterText(confirmationField, 'second-password');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
  });

  for (final (name, page, firstLabel, fieldCount) in [
    ('login', const LoginPage(), 'Email address', 2),
    ('register', const RegisterPage(), 'Display name', 4),
    ('forgot password', const ForgotPasswordPage(), 'Email address', 1),
    (
      'reset password',
      const ForgotPasswordPage(isResetLink: true, resetToken: 'test-token'),
      'New password',
      2,
    ),
  ]) {
    testWidgets('$name validates on Continue and focuses the first invalid field', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      expect(find.text('This field is required'), findsNothing);
      expect(find.text('At least 8 characters'), findsNothing);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required'), findsNWidgets(fieldCount));
      final firstField = find.widgetWithText(TextFormField, firstLabel);
      final editable = tester.widget<EditableText>(
        find.descendant(of: firstField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(firstField.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sign-up password length error waits until the user leaves the field', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RegisterPage()));
    final passwordField = find.widgetWithText(TextFormField, 'Password');
    await tester.enterText(passwordField, 'short');
    await tester.pumpAndSettle();
    expect(find.text('At least 8 characters'), findsNothing);
    expect(find.text('Minimum 8 characters'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Minimum 8 characters'), findsOneWidget);
    expect(find.text('This field is required'), findsNothing);
    final emailField = find.widgetWithText(TextFormField, 'Email address');
    final confirmationField = find.widgetWithText(TextFormField, 'Confirm password');
    await tester.enterText(emailField, 'reader@');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email'), findsOneWidget);

    expect(
      tester.getTopLeft(confirmationField).dy - tester.getBottomLeft(passwordField).dy,
      tester.getTopLeft(passwordField).dy - tester.getBottomLeft(emailField).dy,
    );

    await tester.enterText(passwordField, 'long-enough');
    await tester.pumpAndSettle();
    expect(find.text('Minimum 8 characters'), findsNothing);
    expect(find.text('At least 8 characters'), findsNothing);
  });

  testWidgets('keyboard submission scrolls to the first invalid field and preserves entered values', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RegisterPage()));
    await tester.enterText(find.widgetWithText(TextFormField, 'Display name'), 'Reader');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'reader@');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'long-enough');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'long-enough');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final emailField = find.widgetWithText(TextFormField, 'Email address');
    final editable = tester.widget<EditableText>(find.descendant(of: emailField, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.getRect(emailField).bottom, lessThanOrEqualTo(544));
    expect(tester.getRect(emailField).top, greaterThanOrEqualTo(128));
    expect(find.text('Not a valid email'), findsOneWidget);

    expect(
      tester.widgetList<EditableText>(find.byType(EditableText)).map((field) => field.controller.text),
      ['Reader', 'reader@', 'long-enough', 'long-enough'],
    );

    expect(tester.takeException(), isNull);
  });
}
