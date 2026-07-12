import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';

void main() {
  testWidgets('server-backed cover uses the private media renderer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CoverImagePicker(
          bookId: 'book-1',
          mediaId: 'cover-1',
          coverWidth: 200,
          onUrlChanged: (_) {},
          onFileChanged: (_) {},
        ),
      ),
    );

    final cover = tester.widget<PrivateBookCover>(find.byType(PrivateBookCover));
    expect(cover.bookId, 'book-1');
    expect(cover.mediaId, 'cover-1');
  });
}
