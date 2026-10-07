import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:papyrus/services/reading_device_identity.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manual, reader completion and undo use a persistent installation identity', () async {
    SharedPreferences.setMockInitialValues({ReadingDeviceIdentity.preferenceKey: 'installation-one'});
    final preferences = await SharedPreferences.getInstance();
    await ReadingDeviceIdentity.initialize(preferences);
    final now = DateTime.now().toUtc();
    final book = Book(id: 'identity-book', title: 'Book', author: '', addedAt: now);
    final store = DataStore()..loadData(books: [book]);
    final provider = GoalsProvider(now: () => now, watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await provider.logReading(book: book, end: now, minutes: 10);
    expect(store.readingActivities.single.deviceId, 'installation-one');
    expect(store.readingActivities.single.source, 'manual');
    final completion = store
        .completionChanges(book.copyWith(readingStatus: LibraryReadingStatus.completed), book, source: 'reader')
        .single;
    expect(completion.source, 'reader');
    expect(completion.deviceId, 'installation-one');
    expect(store.reversalFor(completion).deviceId, 'installation-one');
    await ReadingDeviceIdentity.initialize(preferences);
    expect(ReadingDeviceIdentity.current, 'installation-one');
  });
  test('configuration replacement archives the old rules and starts at the replacement cutoff', () async {
    var now = DateTime.utc(2026, 10, 5, 12);
    final book = Book(id: 'book', title: 'Book', author: '', addedAt: now);
    final store = DataStore()..loadData(books: [book]);
    final provider = GoalsProvider(now: () => now, watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await provider.createGoal(type: GoalType.minutes, target: 30, period: GoalPeriod.daily, timezone: 'UTC');
    final original = store.goalDefinitions.single;
    now = now.add(const Duration(hours: 1));
    await provider.logReading(book: book, end: now, minutes: 10, pages: 12);
    now = now.add(const Duration(hours: 1));
    await expectLater(
      provider.createGoal(
        type: GoalType.pages,
        target: 100,
        period: GoalPeriod.weekly,
        scope: GoalScope.book,
        replaceGoalId: original.id,
        timezone: 'UTC',
      ),
      throwsArgumentError,
    );
    expect(store.goalDefinitions.single.isArchived, isFalse);
    await provider.createGoal(
      type: GoalType.pages,
      target: 100,
      period: GoalPeriod.weekly,
      scope: GoalScope.book,
      scopeId: book.id,
      replaceGoalId: original.id,
      timezone: 'UTC',
    );
    final retained = store.getReadingGoal(original.id)!;
    expect(retained.isArchived, isTrue);
    expect(retained.type, GoalType.minutes);
    expect(provider.progress(retained).seconds, 600);
    expect(store.readingActivities.length, 1);
    expect(provider.current.single.pages, 0);
    expect(provider.current.single.goal.createdAt, now);
    now = now.add(const Duration(hours: 1));
    await provider.logReading(book: store.getBook(book.id)!, end: now, pages: 5);
    expect(provider.current.single.pages, 5);
    expect(provider.progress(retained).seconds, 600);
  });
  test('selected books are canonical, bounded, durable and exclude other completions', () async {
    var now = DateTime.utc(2026, 10, 5, 12);
    final books = [
      for (final id in ['a', 'b', 'c']) Book(id: id, title: id, author: '', addedAt: now),
    ];
    final store = DataStore()..loadData(books: books);
    final provider = GoalsProvider(now: () => now, watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await expectLater(
      provider.createGoal(
        type: GoalType.books,
        target: 12,
        period: GoalPeriod.yearly,
        scope: GoalScope.book,
        scopeId: 'a',
        timezone: 'UTC',
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.createGoal(
        type: GoalType.books,
        target: 3,
        period: GoalPeriod.yearly,
        scope: GoalScope.book,
        bookIds: ['a', 'b', 'b'],
        timezone: 'UTC',
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.createGoal(
        type: GoalType.minutes,
        target: 30,
        period: GoalPeriod.daily,
        scope: GoalScope.book,
        bookIds: List.generate(1001, (i) => 'book-$i'),
        timezone: 'UTC',
      ),
      throwsArgumentError,
    );
    await provider.createGoal(
      type: GoalType.books,
      target: 2,
      period: GoalPeriod.yearly,
      scope: GoalScope.book,
      bookIds: ['b', 'a', 'a'],
      timezone: 'UTC',
    );
    final goal = store.goalDefinitions.single;
    expect(goal.scopeId, 'a');
    expect(ReadingGoal.fromJson(goal.toJson()).selectedBookIds, ['a', 'b']);
    await expectLater(provider.updateGoal(goalId: goal.id, target: 3), throwsArgumentError);
    now = now.add(const Duration(minutes: 1));
    for (final book in books) {
      await provider.logReading(book: store.getBook(book.id)!, end: now, finished: true);
    }
    expect(provider.current.single.finishedBooks, 2);
    final completion = store.effectiveReadingActivities.firstWhere((a) => a.kind == 'completion' && a.bookId == 'b');
    await provider.reverseActivity(completion);
    expect(provider.current.single.finishedBooks, 1);
    final single = goal.copyWith(bookIds: [], scopeId: 'b');
    expect(single.toJson().containsKey('book_ids'), isFalse);
    expect(ReadingGoal.fromJson(single.toJson()).selectedBookIds, ['b']);
  });

  test('recurrence, manual correction, deletion and completion undo retain durable history', () async {
    var now = DateTime.utc(2026, 10, 5, 12);
    final book = Book(id: 'book', title: 'Physical book', author: '', addedAt: now, isPhysical: true);
    final store = DataStore()..loadData(books: [book]);
    final provider = GoalsProvider(now: () => now)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await provider.createGoal(type: GoalType.minutes, target: 30, period: GoalPeriod.daily, timezone: 'UTC');
    now = now.add(const Duration(hours: 1));
    await provider.logReading(book: book, end: now, minutes: 35, pages: 12);
    expect(provider.current.single.reached, isTrue);
    expect(store.goalDefinitions.single.isArchived, isFalse);
    final original = store.effectiveReadingActivities.single;
    await provider.logReading(book: store.getBook(book.id)!, end: now, minutes: 15, correcting: original);
    expect(provider.current.single.seconds, 900);
    expect(store.readingActivities.length, 3);
    now = DateTime.utc(2026, 10, 6, 12);
    await provider.refresh();
    expect(provider.current.single.seconds, 0);
    expect(provider.history.single.seconds, 900);
    await provider.updateGoal(goalId: store.goalDefinitions.single.id, target: 10);
    expect(provider.history.single.goal.targetValue, 30);
    await provider.logReading(book: store.getBook(book.id)!, end: now, minutes: 20, finished: true);
    expect(store.getBook(book.id)!.readingStatus, LibraryReadingStatus.completed);
    final completion = store.effectiveReadingActivities.firstWhere((a) => a.kind == 'completion');
    await provider.reverseActivity(completion);
    expect(store.getBook(book.id)!.readingStatus, LibraryReadingStatus.inProgress);
    await provider.deleteGoal(store.goalDefinitions.single.id);
    expect(store.goalDefinitions, isEmpty);
    expect(store.goalPeriods.length, 2);
    expect(store.readingActivities, isNotEmpty);
    expect(provider.history.first.seconds, 1200);
  });
}
