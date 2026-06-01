import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/auth/auth_page_layouts.dart';

void main() {
  testWidgets('desktop swap button is focused after form controls', (tester) async {
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
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: DesktopAuthLayout(
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
