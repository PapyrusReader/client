import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/note_dialog.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';

void main() {
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
    expect(sheetBottom - tagsBottom, lessThan(80));
  });
}
