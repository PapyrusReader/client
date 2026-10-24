import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/widgets/library/book_list_item.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final shelfView in [false, true]) {
    testWidgets('last book favorite stays tappable above the FAB, shelf: $shelfView', (tester) async {
      const size = Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final shelf = buildTestShelf();
      final books = List.generate(20, (index) => buildTestBook(id: 'book-$index', title: 'Book $index'));
      final store = createTestDataStore(books: books, shelves: [shelf]);

      store.loadData(
        bookShelfRelations: [
          for (final book in books) BookShelfRelation(bookId: book.id, shelfId: shelf.id, addedAt: DateTime(2026)),
        ],
      );

      final provider = LibraryProvider(dataStore: store)..setViewMode(LibraryViewMode.list);

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        store.dispose();
      });

      await tester.pumpWidget(
        createTestPage(
          dataStore: store,
          libraryProvider: provider,
          screenSize: size,
          page: MediaQuery(
            data: const MediaQueryData(size: size, padding: EdgeInsets.only(bottom: 24)),
            child: Scaffold(
              body: LibraryPage(shelf: shelfView ? shelf : null),
              bottomNavigationBar: const SizedBox(height: 80),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final list = find.descendant(of: find.byType(LibraryPage), matching: find.byType(ListView)).last;
      await tester.drag(list, const Offset(0, -10000));
      await tester.pumpAndSettle();
      final lastBook = find.byType(BookListItem).last;
      final bookId = tester.widget<BookListItem>(lastBook).book.id;
      expect(tester.getRect(lastBook).bottom, lessThan(tester.getRect(find.byType(FloatingActionButton)).top));
      final favorite = find.descendant(of: lastBook, matching: find.byTooltip('Add to favorites'));
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(store.getBook(bookId)!.isFavorite, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
