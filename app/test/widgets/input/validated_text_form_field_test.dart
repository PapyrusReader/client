import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/input/validated_text_form_field.dart';

void main() {
  testWidgets('controller ownership can change while editing without losing values or disposing external controllers', (
    tester,
  ) async {
    final external = TextEditingController(text: 'external');
    final replacement = TextEditingController(text: 'replacement');
    addTearDown(external.dispose);
    addTearDown(replacement.dispose);
    TextEditingController? retiringController;

    Future<void> pumpField(TextEditingController? controller) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValidatedTextFormField(
              controller: controller,
              validator: (_) => null,
              decoration: InputDecoration(
                labelText: 'Name',
                prefix: Builder(
                  builder: (context) {
                    final retiring = retiringController;

                    if (retiring != null) {
                      // Descendants must be able to release the old input state during their update.
                      expect(ChangeNotifier.debugAssertNotDisposed(retiring), isTrue);
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpField(null);
    await tester.enterText(find.byType(TextFormField), 'typed');
    final internal = tester.widget<EditableText>(find.byType(EditableText)).controller;
    retiringController = internal;
    await pumpField(external);
    retiringController = null;
    expect(tester.takeException(), isNull);
    expect(find.text('external'), findsOneWidget);
    expect(() => ChangeNotifier.debugAssertNotDisposed(internal), throwsFlutterError);
    await pumpField(replacement);
    external.text = 'still usable';
    expect(find.text('replacement'), findsOneWidget);
    replacement.selection = const TextSelection.collapsed(offset: 4);
    await pumpField(null);
    final newInternal = tester.widget<EditableText>(find.byType(EditableText)).controller;
    expect(newInternal.value, replacement.value);
    replacement.text = 'also usable';
    expect(newInternal.text, 'replacement');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => ChangeNotifier.debugAssertNotDisposed(newInternal), throwsFlutterError);
    external.text = 'usable after unmount';
    replacement.text = 'usable after unmount';
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus ownership can change while focused and leaves external nodes usable', (tester) async {
    final external = FocusNode();
    final replacement = FocusNode();
    addTearDown(external.dispose);
    addTearDown(replacement.dispose);
    FocusNode? retiringFocus;

    Future<void> pumpField(FocusNode? focusNode) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValidatedTextFormField(
              focusNode: focusNode,
              validator: (_) => null,
              decoration: InputDecoration(
                labelText: 'Name',
                prefix: Builder(
                  builder: (context) {
                    final retiring = retiringFocus;

                    if (retiring != null) {
                      expect(ChangeNotifier.debugAssertNotDisposed(retiring), isTrue);
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpField(null);
    await tester.enterText(find.byType(TextFormField), 'typed');
    final internal = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(internal.hasFocus, isTrue);
    retiringFocus = internal;
    await pumpField(external);
    retiringFocus = null;
    expect(tester.takeException(), isNull);
    expect(() => ChangeNotifier.debugAssertNotDisposed(internal), throwsFlutterError);
    external.requestFocus();
    await tester.pump();
    expect(external.hasFocus, isTrue);
    await pumpField(replacement);
    expect(ChangeNotifier.debugAssertNotDisposed(external), isTrue);
    replacement.requestFocus();
    await tester.pump();
    expect(replacement.hasFocus, isTrue);
    await pumpField(null);
    final newInternal = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    newInternal.requestFocus();
    await tester.pump();
    expect(newInternal.hasFocus, isTrue);
    expect(ChangeNotifier.debugAssertNotDisposed(replacement), isTrue);
    expect(find.text('typed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => ChangeNotifier.debugAssertNotDisposed(newInternal), throwsFlutterError);
    expect(ChangeNotifier.debugAssertNotDisposed(external), isTrue);
    expect(ChangeNotifier.debugAssertNotDisposed(replacement), isTrue);
    expect(tester.takeException(), isNull);
  });
}
