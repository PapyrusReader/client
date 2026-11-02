import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/statistics_provider.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final now in [DateTime(2026, 11, 2, 12), DateTime(2026, 11, 4, 12), DateTime(2026, 11, 8, 12)]) {
    test('calendar charts retain empty future buckets on weekday ${now.weekday}', () async {
      final store = DataStore()..loadData();
      addTearDown(store.dispose);
      final monday = DateTime(2026, 11, 2);
      await store.commitTracking(
        activities: [
          ReadingActivity(
            id: 'monday',
            bookId: 'book',
            bookTitle: 'Book',
            startTime: monday,
            endTime: monday.add(const Duration(minutes: 7)),
            createdAt: monday.add(const Duration(minutes: 7)),
            pages: 2,
          ),
        ],
      );
      final provider = StatisticsProvider(now: () => now)..attach(store);
      addTearDown(provider.dispose);
      expect(provider.readingTimeData.length, 7);
      expect(provider.readingTimeData.last.date, DateTime(2026, 11, 8));
      expect(provider.readingTimeData.first.seconds, 420);
      expect(provider.readingTimeData.skip(1).every((day) => day.seconds == 0 && day.pages == 0), isTrue);
      expect(provider.totalReadingSeconds, 420);
      expect(provider.pagesRead, 2);
      expect(provider.periodDays, now.weekday);
      expect(provider.averageDailyMinutes, (7 / now.weekday).round());
      provider.setPeriod(StatsPeriod.month);
      expect(provider.readingTimeData.length, 30);
      expect(provider.periodDays, now.day);
      provider.setPeriod(StatsPeriod.year);
      expect(provider.bucketSize, StatisticsBucketSize.month);
      expect(provider.readingTimeData.length, 12);
      expect(provider.readingTimeData.last.date, DateTime(2026, 12));
      expect(provider.readingTimeData.last.seconds, 0);
    });
  }

  test('January uses twelve monthly ticks from the first day', () {
    final store = DataStore()..loadData();
    addTearDown(store.dispose);
    final provider = StatisticsProvider(now: () => DateTime(2026, 1, 1, 12))..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.year);
    expect(provider.bucketSize, StatisticsBucketSize.month);
    expect(provider.readingTimeData.length, 12);
    expect(provider.periodDays, 1);
  });

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
    expect(provider.monthlyStats.first.booksRead, 1);
    expect(provider.readingTimeData.last.booksRead, unorderedEquals(['legacy-today', 'tracked']));
    provider.setCustomDateRange(previousMonth, previousMonth);
    expect(provider.totalBooks, 1);
    expect(store.readingActivities.where((activity) => activity.bookId.startsWith('legacy')), isEmpty);
  });
  test('full-period buckets preserve old activity and fractional minutes', () async {
    final store = DataStore()..loadData();
    addTearDown(store.dispose);
    final now = DateTime(2026, 11, 2, 12);

    ReadingActivity reading(String id, DateTime start, int seconds, int pages) => ReadingActivity(
      id: id,
      bookId: id,
      bookTitle: id,
      startTime: start,
      endTime: start.add(Duration(seconds: seconds)),
      createdAt: start,
      pages: pages,
    );

    await store.commitTracking(
      activities: [
        reading('january', DateTime(2026, 1, 10), 30, 4),
        reading('october', DateTime(2026, 10, 15), 30, 6),
        reading('november', DateTime(2026, 11, 1), 600, 12),
      ],
    );

    final provider = StatisticsProvider(now: () => now)..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.year);
    expect(provider.bucketSize, StatisticsBucketSize.month);
    expect(provider.readingTimeData.length, 12);
    expect(provider.readingTimeData.first.seconds, 30);
    expect(provider.readingTimeData.fold<int>(0, (sum, bucket) => sum + bucket.seconds), 660);
    expect(provider.readingTimeData.fold<double>(0, (sum, bucket) => sum + bucket.pages), 22);
    expect(provider.totalReadingSeconds, 660);
    expect(provider.pagesRead, 22);
    expect(provider.periodDays, 306);
    expect(provider.averageReadingLabel, '2s');
    expect(provider.monthlyStats.length, 11);

    provider.setCustomDateRange(DateTime(2026, 10, 15), DateTime(2026, 11, 1));
    expect(provider.bucketSize, StatisticsBucketSize.day);
    expect(provider.periodDays, 18);
    expect(provider.totalReadingSeconds, 630);
    expect(provider.readingTimeData.first.date, DateTime(2026, 10, 15));
    expect(provider.readingTimeData.last.endDate, DateTime(2026, 11, 2));
    expect(provider.averageReadingLabel, '35s');
  });

  test('genres count distinct books read in range and respect corrections', () async {
    final now = DateTime(2026, 11, 2, 12);
    final store = DataStore()
      ..loadData(
        books: [
          for (final id in ['read', 'old', 'undone', 'unread'])
            Book(id: id, title: id, author: '', addedAt: now, customMetadata: {'genre': id}),
        ],
      );
    addTearDown(store.dispose);

    ReadingActivity reading(String id, String bookId, DateTime start) => ReadingActivity(
      id: id,
      bookId: bookId,
      bookTitle: bookId,
      startTime: start,
      endTime: start.add(const Duration(minutes: 10)),
      createdAt: start,
    );

    final undone = reading('undo', 'undone', DateTime(2026, 11, 1));

    await store.commitTracking(
      activities: [
        reading('one', 'read', DateTime(2026, 11, 1)),
        reading('two', 'read', DateTime(2026, 11, 2)),
        reading('old', 'old', DateTime(2026, 9, 1)),
        undone,
        store.reversalFor(undone),
      ],
    );

    final provider = StatisticsProvider(now: () => now)..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.month);
    expect(provider.booksRead, 1);
    expect(provider.daysRead, 2);
    expect(provider.genreDistribution.single.genre, 'read');
    expect(provider.genreDistribution.single.bookCount, 1);
    expect(provider.genreDistribution.single.percentage, 1);
    final book = store.getBook('read')!;
    await store.updateBookAndWait(book.copyWith(customMetadata: {'genre': 'Science fiction'}), previous: book);
    expect(provider.genreDistribution.single.genre, 'Science fiction');
    await store.updateBookAndWait(book, previous: store.getBook('read'));

    provider.setPeriod(StatsPeriod.allTime);
    expect(provider.booksRead, 2);
    expect(provider.genreDistribution.map((genre) => genre.genre), unorderedEquals(['read', 'old']));

    final emptyStore = DataStore()..loadData();
    addTearDown(emptyStore.dispose);
    provider.attach(emptyStore);
    expect(provider.totalReadingSeconds, 0);
    expect(provider.daysRead, 0);
    expect(provider.booksRead, 0);
    expect(provider.genreDistribution, isEmpty);
  });

  test('long history uses yearly buckets and custom boundaries clip cross-midnight sessions', () async {
    final store = DataStore()..loadData();
    addTearDown(store.dispose);
    final start = DateTime(2020, 1, 31, 23, 50);

    await store.commitTracking(
      activities: [
        ReadingActivity(
          id: 'cross-midnight',
          bookId: 'book',
          bookTitle: 'Book',
          startTime: start,
          endTime: start.add(const Duration(minutes: 20)),
          createdAt: start,
          pages: 8,
        ),
      ],
    );

    final provider = StatisticsProvider(now: () => DateTime(2026, 11, 2))..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.allTime);
    expect(provider.bucketSize, StatisticsBucketSize.year);
    expect(provider.readingTimeData.length, 7);
    expect(provider.readingTimeData.first.date, DateTime(2020, 1, 31));
    expect(provider.totalReadingSeconds, 1200);
    expect(provider.periodDays, DateTime.utc(2026, 11, 3).difference(DateTime.utc(2020, 1, 31)).inDays);
    provider.setCustomDateRange(DateTime(2020, 2, 1), DateTime(2020, 2, 1));
    expect(provider.totalReadingSeconds, 600);
    expect(provider.daysRead, 1);
    expect(provider.pagesRead, 8);
    expect(provider.readingTimeData.single.seconds, 600);
    expect(provider.sessionStats.totalSessions, 1);
  });

  test('reading days use the established five-minute threshold', () async {
    final store = DataStore()..loadData();
    addTearDown(store.dispose);

    await store.commitTracking(
      activities: [
        for (var day = 1; day <= 2; day++)
          ReadingActivity(
            id: '$day',
            bookId: 'book',
            bookTitle: 'Book',
            startTime: DateTime(2026, 11, day),
            endTime: DateTime(2026, 11, day, 0, day + 3),
            createdAt: DateTime(2026, 11, day),
          ),
      ],
    );

    final provider = StatisticsProvider(now: () => DateTime(2026, 11, 2, 12))..attach(store);
    addTearDown(provider.dispose);
    provider.setPeriod(StatsPeriod.month);
    expect(provider.daysRead, 1);
    expect(provider.totalReadingMinutes, 9);
    expect(provider.averageDailyMinutes, 5);
  });
}
