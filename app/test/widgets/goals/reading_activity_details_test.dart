import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/shared/searchable_book_field.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('activity presents book metadata and a single safe footer at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      final now = DateTime.now().toUtc();
      final book = Book(id: 'book', title: 'Alice’s Adventures in Wonderland', author: 'Lewis Carroll', addedAt: now);
      final entry = ReadingActivity(
        id: 'entry',
        bookId: book.id,
        bookTitle: book.title,
        kind: 'completion',
        startTime: now,
        endTime: now,
        createdAt: now,
        note: 'A lovely ending.',
      );
      final store = DataStore()..loadData(books: [book]);
      await store.commitTracking(activities: [entry]);
      final provider = GoalsProvider(watchClock: false)..attach(store);
      addTearDown(provider.dispose);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(width < 500 ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: ReadingActivityTile(activity: entry, provider: provider),
          ),
        ),
      );
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();
      expect(find.text(book.author), findsOneWidget);
      expect(find.byType(CoverImagePreview), findsOneWidget);
      expect(find.text('Finished book'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text(entry.note!), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      final done = find.widgetWithText(FilledButton, 'Done');
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getRect(done).bottom, lessThanOrEqualTo(952));
      await tester.ensureVisible(find.text('Undo this entry'));
      await tester.tap(find.text('Undo this entry'));
      await tester.pumpAndSettle();
      expect(find.text('Undo reading entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Undo entry'));
      await tester.pumpAndSettle();
      expect(store.readingActivities.any((a) => a.kind == 'reversal' && a.correctionOf == entry.id), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('correction uses fixed book context and saves to the original book', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();
    final book = Book(id: 'alice', title: 'Alice’s Adventures in Wonderland', author: 'Lewis Carroll', addedAt: now);
    final entry = ReadingActivity(
      id: 'entry',
      bookId: book.id,
      bookTitle: book.title,
      kind: 'completion',
      startTime: now,
      endTime: now,
      createdAt: now,
    );
    final store = DataStore()..loadData(books: [book]);
    await store.commitTracking(activities: [entry]);
    final provider = GoalsProvider(watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => LogReadingSheet.show(context, provider: provider, book: book, correcting: entry),
              child: const Text('Correct'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchableBookField), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.text(book.title), findsOneWidget);
    expect(find.text(book.author), findsOneWidget);
    expect(find.byType(CoverImagePreview), findsOneWidget);
    final note = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Note (optional)',
    );
    await tester.enterText(note, 'Updated note');
    await tester.tap(find.widgetWithText(FilledButton, 'Save reading'));
    await tester.pumpAndSettle();
    expect(store.readingActivities.where((a) => a.kind == 'reversal' && a.correctionOf == entry.id), hasLength(1));
    final replacement = store.readingActivities.singleWhere((a) => a.note == 'Updated note');
    expect(replacement.bookId, book.id);
    expect(replacement.kind, 'completion');
    expect(tester.takeException(), isNull);
  });
  testWidgets('removed book retains title and precise reader duration without correction controls', (tester) async {
    final now = DateTime.now().toUtc();
    final entry = ReadingActivity(
      id: 'entry',
      bookId: 'removed',
      bookTitle: 'Remembered book',
      source: 'reader',
      startTime: now.subtract(const Duration(seconds: 34)),
      endTime: now,
      createdAt: now,
    );
    final store = DataStore();
    final provider = GoalsProvider(watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ReadingActivityTile(activity: entry, provider: provider),
        ),
      ),
    );
    await tester.tap(find.text(entry.bookTitle));
    await tester.pumpAndSettle();
    expect(find.text(entry.bookTitle), findsWidgets);
    expect(find.text('34 sec'), findsOneWidget);
    expect(find.text('This book is no longer in your library.'), findsOneWidget);
    expect(find.text('Correct entry'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
