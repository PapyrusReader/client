import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/pages/shelf_contents_page.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book/book_details.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

void main() {
  for (final width in [400.0, 1200.0]) {
    testWidgets('book details shelf chip opens the selected shelf at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      addTearDown(tester.view.reset);
      final book = buildTestBook(id: 'book', title: 'A book on both shelves');
      final otherBook = buildTestBook(id: 'other', title: 'Only on the first shelf');
      final firstShelf = buildTestShelf(id: 'first', name: 'First shelf');
      final secondShelf = buildTestShelf(id: 'second', name: 'Second shelf');
      final store = createTestDataStore(books: [book, otherBook], shelves: [firstShelf, secondShelf]);

      store.loadData(
        bookShelfRelations: [
          BookShelfRelation(bookId: book.id, shelfId: firstShelf.id, addedAt: DateTime(2026)),
          BookShelfRelation(bookId: book.id, shelfId: secondShelf.id, addedAt: DateTime(2026)),
          BookShelfRelation(bookId: otherBook.id, shelfId: firstShelf.id, addedAt: DateTime(2026)),
        ],
      );

      final library = LibraryProvider();
      final router = GoRouter(
        initialLocation: '/library/details/book',
        routes: [
          GoRoute(
            path: '/library/details/:bookId',
            builder: (context, state) => Scaffold(body: BookDetails(book: book)),
          ),
          GoRoute(
            name: 'SHELF_CONTENTS',
            path: '/library/shelves/:shelfId',
            builder: (context, state) => ShelfContentsPage(shelfId: state.pathParameters['shelfId']),
          ),
        ],
      );

      addTearDown(router.dispose);
      addTearDown(library.dispose);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider.value(value: library),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      final chip = find.widgetWithText(ActionChip, 'Second shelf');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/library/shelves/second');
      expect(find.byType(ShelfContentsPage), findsOneWidget);
      expect(find.text('Second shelf'), findsOneWidget);
      expect(find.text('A book on both shelves'), findsWidgets);
      expect(find.text('Only on the first shelf'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
