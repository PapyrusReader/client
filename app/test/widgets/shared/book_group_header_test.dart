import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/shared/book_group_header.dart';

void main() {
  testWidgets('book group header forwards the grouped book id to its cover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookGroupHeader(
            bookId: 'book-1',
            bookTitle: 'Book',
            coverUrl: 'https://example.test/cover.jpg',
            count: 1,
            itemLabel: 'note',
            isCollapsed: false,
            onToggle: () {},
          ),
        ),
      ),
    );

    expect(tester.widget<PrivateBookCover>(find.byType(PrivateBookCover)).bookId, 'book-1');
  });
}
