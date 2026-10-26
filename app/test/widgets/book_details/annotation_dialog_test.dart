import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/widgets/book_details/annotation_dialog.dart';

void main() {
  testWidgets('reader annotation hides location while preserving its saved anchor', (tester) async {
    const location = BookLocation(
      pageNumber: 1,
      chapterTitle: 'CHAPTER VI. Pig and Pepper',
      percentage: .4,
      readerLocator: {'type': 'epub', 'spineIndex': 6, 'textOffset': 123},
    );
    Annotation? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AnnotationDialog.show(
                context,
                bookId: 'book',
                initialText: 'Selected passage',
                initialLocation: location,
                onSave: (annotation) => saved = annotation,
              ),
              child: const Text('Annotate'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Annotate'));
    await tester.pumpAndSettle();
    expect(find.text(location.displayLocation), findsNothing);
    expect(find.text('Page number'), findsNothing);
    expect(find.text('Chapter title (optional)'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Note (optional)'), 'My annotation');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.location, location);
    expect(saved?.selectedText, 'Selected passage');
    expect(saved?.note, 'My annotation');
    expect(tester.takeException(), isNull);
  });

  for (final anchored in [false, true]) {
    testWidgets('annotation editing hides and preserves location, anchored $anchored', (tester) async {
      final existing = Annotation(
        id: 'annotation',
        bookId: 'book',
        selectedText: 'Selected passage',
        location: BookLocation(
          pageNumber: 30,
          chapterTitle: 'CHAPTER VI. Pig and Pepper',
          percentage: .4,
          readerLocator: anchored ? {'type': 'epub', 'spineIndex': 6, 'textOffset': 123} : null,
        ),
        createdAt: DateTime.utc(2026),
      );
      Annotation? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AnnotationDialog.show(
                  context,
                  bookId: existing.bookId,
                  existingAnnotation: existing,
                  onSave: (annotation) => saved = annotation,
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text(existing.location.displayLocation), findsNothing);
      expect(find.text('Page number'), findsNothing);
      expect(find.text('Chapter title (optional)'), findsNothing);
      await tester.enterText(find.widgetWithText(TextFormField, 'Note (optional)'), 'Updated annotation');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.location, existing.location);
      expect(saved!.note, 'Updated annotation');
      expect(tester.takeException(), isNull);
    });
  }

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
