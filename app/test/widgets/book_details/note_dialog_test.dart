import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyrus/models/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/note_dialog.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/themes/design_tokens.dart';

void main() {
  testWidgets('full screen keeps the note draft and only form Save persists it', (tester) async {
    Note? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => NoteDialog.show(context, bookId: 'book', onSave: (note) => saved = note),
              child: const Text('Add note'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Reading notes');
    await tester.enterText(find.byKey(const Key('note-content-field')), 'First paragraph');
    await tester.ensureVisible(find.byTooltip('Edit in full screen'));
    await tester.tap(find.byTooltip('Edit in full screen'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('fullscreen-note-field'));
    expect(tester.widget<TextField>(editor).controller!.text, 'First paragraph');
    await tester.enterText(editor, 'First paragraph\n\nAnother thought');
    expect(saved, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    expect(find.widgetWithText(TextField, 'First paragraph\n\nAnother thought'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Reading notes'), findsOneWidget);
    expect(saved, isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.content, 'First paragraph\n\nAnother thought');
    expect(saved?.title, 'Reading notes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('content field uses a bounded multiline height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => NoteDialog.show(context, bookId: 'book-1'),
              child: const Text('Add note'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    final contentField = find.byKey(const Key('note-content-field'));

    final editableText = tester.widget<EditableText>(
      find.descendant(of: contentField, matching: find.byType(EditableText)),
    );

    expect(editableText.expands, isFalse);
    expect(editableText.minLines, 8);
    expect(editableText.maxLines, 12);
    await tester.drag(find.byType(BottomSheetHandle), const Offset(0, -300));
    await tester.pumpAndSettle();
    final sheetBottom = tester.getBottomRight(find.byKey(const Key('note-bottom-sheet'))).dy;
    final tagsBottom = tester.getBottomRight(find.text('Tags will appear here')).dy;
    final footer = tester.getRect(find.byType(BottomSheetFooter));
    expect(footer.top - tagsBottom, lessThanOrEqualTo(Spacing.lg));
    expect(sheetBottom, footer.bottom);
  });
}
