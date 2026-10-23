import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shelves/shelf_info_sheet.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('shelf info counts only member books and follows library changes', (tester) async {
    final shelf = buildTestShelf();
    final completed = buildTestBook(id: 'completed', readingStatus: LibraryReadingStatus.completed);
    final reading = buildTestBook(id: 'reading', readingStatus: LibraryReadingStatus.inProgress);
    final unread = buildTestBook(id: 'unread', readingStatus: LibraryReadingStatus.unread);
    final other = buildTestBook(id: 'other', readingStatus: LibraryReadingStatus.completed);

    final store = DataStore()
      ..loadData(
        shelves: [shelf],
        books: [completed, reading, unread, other],
        bookShelfRelations: [
          for (final book in [completed, reading, unread])
            BookShelfRelation(bookId: book.id, shelfId: shelf.id, addedAt: DateTime(2026)),
        ],
      );

    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ShelfInfoSheet.show(context, shelfId: shelf.id),
                child: const Text('Info'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('No description yet.'), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);
    expect(find.text('1 reading'), findsOneWidget);
    expect(find.text('1 not started'), findsOneWidget);
    expect(find.text('Jan 1, 2025'), findsOneWidget);

    store.loadData(
      books: [
        completed,
        reading.copyWith(readingStatus: LibraryReadingStatus.completed),
        unread,
        other,
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('2 completed'), findsOneWidget);
    expect(find.text('1 reading'), findsNothing);
    expect(find.text('3 books'), findsOneWidget);

    store.loadData(
      bookShelfRelations: [BookShelfRelation(bookId: completed.id, shelfId: shelf.id, addedAt: DateTime(2026))],
    );

    await tester.pumpAndSettle();
    expect(find.text('1 book'), findsOneWidget);
    expect(find.text('3 books'), findsNothing);
    store.loadData(bookShelfRelations: []);
    await tester.pumpAndSettle();
    expect(find.text('0 books'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
