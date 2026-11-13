import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/expandable_text_form_field.dart';

void main() {
  testWidgets('validation keeps expand button inside input and expanded edits validate', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final form = GlobalKey<FormState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Form(
            key: form,
            child: ExpandableTextFormField(
              controller: controller,
              label: 'Content',
              hint: 'Write your note...',
              validator: (value) => value == null || value.isEmpty ? 'Content is required' : null,
            ),
          ),
        ),
      ),
    );

    expect(form.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    final button = tester.getRect(find.byTooltip('Edit in full screen'));
    expect(field.contains(button.topLeft), isTrue);
    expect(field.contains(button.bottomRight), isTrue);
    expect(find.text('Content is required'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit in full screen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fullscreen-note-field')), 'A full-screen draft');
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Content is required'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final variant in [
    (name: 'mobile dark', size: const Size(390, 844), theme: AppTheme.dark, scale: 1.0),
    (name: 'mobile e-ink large text', size: const Size(390, 844), theme: AppTheme.eink, scale: 2.0),
    (name: 'desktop light', size: const Size(1280, 900), theme: AppTheme.light, scale: 1.0),
  ]) {
    testWidgets('expanded draft survives back and keyboard resize, ${variant.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = variant.size;
      addTearDown(tester.view.reset);
      final controller = TextEditingController(text: 'A passage worth remembering.');
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: variant.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(variant.scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ExpandableTextFormField(controller: controller, label: 'Content', hint: 'Write your note...'),
              ),
            ),
          ),
        ),
      );

      const selection = TextSelection(baseOffset: 2, extentOffset: 9);
      controller.selection = selection;
      await tester.tap(find.byTooltip('Edit in full screen'));
      await tester.pumpAndSettle();
      final editor = find.byKey(const Key('fullscreen-note-field'));
      final editable = tester.widget<EditableText>(find.descendant(of: editor, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(controller.selection, selection);
      expect(tester.getSize(find.byType(Dialog)), variant.size);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(editor).dy, lessThanOrEqualTo(variant.size.height - 300));
      final content = List.filled(30, 'A longer thought about this passage.').join('\n\n');
      await tester.enterText(editor, content);
      await tester.pump();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(controller.text, content);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
