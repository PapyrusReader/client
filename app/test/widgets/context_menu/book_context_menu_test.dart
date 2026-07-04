import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/widgets/context_menu/book_context_menu.dart';

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets('mobile context menu shows download book above delete book and invokes callback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    var downloaded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => BookContextMenu.show(
                  context: context,
                  book: _book(),
                  isFavorite: false,
                  onDownload: () => downloaded = true,
                ),
                child: const Text('Open menu'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    final downloadTop = tester.getTopLeft(find.text('Download book')).dy;
    final deleteTop = tester.getTopLeft(find.text('Delete book')).dy;
    expect(downloadTop, lessThan(deleteTop));

    await tester.tap(find.text('Download book'));
    await tester.pumpAndSettle();

    expect(downloaded, isTrue);
  });
}

Book _book() {
  return Book(id: 'book-1', title: 'Book', author: 'Author', fileFormat: BookFormat.epub, addedAt: DateTime.utc(2026));
}
