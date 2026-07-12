import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';

void main() {
  testWidgets('book cover image forwards the book id to its renderer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CoverImagePreview(bookId: 'book-1', imageUrl: 'https://example.test/cover.jpg', bookTitle: 'Book'),
      ),
    );

    final cover = tester.widget<CoverImage>(find.byType(CoverImage));
    expect(cover.bookId, 'book-1');
  });
}
