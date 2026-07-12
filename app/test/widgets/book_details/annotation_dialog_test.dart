import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/annotation_dialog.dart';

void main() {
  testWidgets('annotation sheet sizes to its form content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AnnotationDialog.show(context, bookId: 'book-1'),
              child: const Text('Add annotation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add annotation'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('New annotation'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Highlight color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
