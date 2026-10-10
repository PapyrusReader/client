import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/statistics_provider.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('historical completion dates survive the ledger upgrade without resurrecting undone entries', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final previousMonth = DateTime(now.year, now.month - 1, 15);

    Book completed(String id, DateTime at) => Book(
      id: id,
      title: id,
      author: '',
      addedAt: at,
      readingStatus: LibraryReadingStatus.completed,
      completedAt: at,
    );

    final store = DataStore()
      ..loadData(
        books: [
          completed('legacy-today', today),
          completed('legacy-previous', previousMonth),
          completed('tracked', today),
          completed('undone', today),
        ],
      );

    addTearDown(store.dispose);

    ReadingActivity completion(String id, String bookId) => ReadingActivity(
      id: id,
      bookId: bookId,
      bookTitle: bookId,
      startTime: today,
      endTime: today,
      createdAt: today,
      kind: 'completion',
    );

    final undone = completion('undone-entry', 'undone');

    await store.commitTracking(
      activities: [
        completion('tracked-one', 'tracked'),
        completion('tracked-two', 'tracked'),
        undone,
        store.reversalFor(undone),
      ],
    );

    final provider = StatisticsProvider()..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.allTime);
    expect(provider.totalBooks, 3);
    expect(provider.monthlyStats.last.booksRead, 2);
    expect(provider.monthlyStats[10].booksRead, 1);
    expect(provider.readingTimeData.last.booksRead, unorderedEquals(['legacy-today', 'tracked']));
    provider.setCustomDateRange(previousMonth, previousMonth);
    expect(provider.totalBooks, 1);
    expect(store.readingActivities.where((activity) => activity.bookId.startsWith('legacy')), isEmpty);
  });
}
