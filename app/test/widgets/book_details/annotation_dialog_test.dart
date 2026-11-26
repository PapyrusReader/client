import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/widgets/book_details/annotation_dialog.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('long selected passage and scrollbar reach the end independently at $size', (tester) async {
      final bottomInset = size.width < 600 ? 48.0 : 0.0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.reset);

      final passage = List.generate(
        50,
        (index) => 'Selected paragraph $index with enough words to wrap over several lines.',
      ).join(' ');

      Annotation? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: size.width > 600 ? TargetPlatform.macOS : TargetPlatform.android),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AnnotationDialog.show(
                  context,
                  bookId: 'book',
                  initialText: passage,
                  initialLocation: const BookLocation(pageNumber: 12, readerLocator: {'type': 'pdf', 'pageIndex': 11}),
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
      final quote = find.byKey(const Key('annotation-quote-scroll'));
      expect(find.ancestor(of: quote, matching: find.byType(Scrollbar)), findsOneWidget);
      expect(find.descendant(of: quote, matching: find.byType(Scrollbar)), findsNothing);
      final note = find.widgetWithText(TextField, 'Note (optional)');
      final noteBounds = tester.getRect(note);
      expect(tester.getSize(quote).height, lessThanOrEqualTo(200));
      expect(note.hitTestable(), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(quote).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(quote, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));

      for (var swipe = 0; swipe < 30 && scroll.offset < scroll.position.maxScrollExtent; swipe++) {
        await tester.drag(quote, const Offset(0, -160));
        await tester.pumpAndSettle();
      }

      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      final scrollbarPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.ancestor(of: quote, matching: find.byType(Scrollbar)),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
          ),
        ),
      );

      final quoteSize = tester.getSize(quote);

      expect(
        (Canvas canvas) => scrollbarPaint.foregroundPainter!.paint(canvas, quoteSize),
        paints..something((method, arguments) {
          final Rect bounds;

          if (method == #drawRect) {
            bounds = arguments.first as Rect;
          } else if (method == #drawRRect) {
            bounds = (arguments.first as RRect).outerRect;
          } else {
            return false;
          }

          final paint = arguments.last as Paint;
          return paint.color.a > 0 && (bounds.bottom - quoteSize.height).abs() < 1;
        }),
        reason: 'The thumb must reach the quote viewport edge, without reserving the phone navigation inset.',
      );

      expect(tester.getRect(note), noteBounds);

      expect(
        tester.getBottomRight(find.widgetWithText(FilledButton, 'Save')).dy,
        lessThanOrEqualTo(size.height - bottomInset),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.selectedText, passage);
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.widgetWithText(TextFormField, 'Highlighted text'), findsNothing);
    expect(find.widgetWithText(SelectableText, 'Selected passage'), findsOneWidget);
    expect(find.text('Page number'), findsNothing);
    expect(find.text('Chapter title (optional)'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'My annotation');
    await tester.tap(find.byTooltip('Edit in full screen'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.enterText(find.byKey(const Key('fullscreen-note-field')), 'My expanded annotation');
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'My expanded annotation'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.location, location);
    expect(saved?.selectedText, 'Selected passage');
    expect(saved?.note, 'My expanded annotation');
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
      expect(find.widgetWithText(TextFormField, 'Highlighted text'), anchored ? findsNothing : findsOneWidget);

      if (!anchored) {
        await tester.enterText(find.widgetWithText(TextFormField, 'Highlighted text'), 'Edited physical passage');
      }

      expect(find.text('Page number'), findsNothing);
      expect(find.text('Chapter title (optional)'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'Updated annotation');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.location, existing.location);
      expect(saved!.note, 'Updated annotation');
      expect(saved!.selectedText, anchored ? 'Selected passage' : 'Edited physical passage');
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
