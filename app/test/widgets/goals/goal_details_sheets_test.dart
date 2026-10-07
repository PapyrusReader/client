import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('partial manual time agrees with goal summary and retains original entries at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1200);
      addTearDown(tester.view.reset);
      final now = DateTime.utc(2026, 10, 8, 0, 36);
      final book = Book(id: 'book', title: 'SQL Performance Explained', author: 'Markus Winand', addedAt: now);
      final goal = ReadingGoal(
        id: 'daily',
        type: GoalType.minutes,
        targetValue: 30,
        period: GoalPeriod.daily,
        startDate: DateTime.utc(2026, 10, 8),
        endDate: DateTime.utc(2026, 10, 9),
        createdAt: now.subtract(const Duration(seconds: 30)),
        scope: GoalScope.book,
        scopeId: book.id,
      );
      final store = DataStore()..loadData(books: [book], readingGoals: [goal]);
      await store.commitTracking(
        activities: [
          for (var i = 0; i < 3; i++)
            ReadingActivity(
              id: 'manual-$i',
              bookId: book.id,
              bookTitle: book.title,
              startTime: now.subtract(const Duration(minutes: 30)),
              endTime: now,
              createdAt: now,
            ),
        ],
      );
      final provider = GoalsProvider(now: () => now, watchClock: false)..attach(store);
      addTearDown(provider.dispose);
      addTearDown(store.dispose);
      expect(goalCount(provider.progress(goal)), '30 sec / 30m');
      expect(goalRemaining(provider.progress(goal)), '29m 30s to go');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => GoalDetailsSheet.show(context, goal: goal, provider: provider),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('30 sec / 30m'), findsOneWidget);
      expect(find.text('0 / 30 minutes'), findsNothing);
      expect(find.text('29m 30s to go'), findsOneWidget);
      expect(find.text('30 sec for this goal'), findsNWidgets(3));
      expect(find.text('30 min · Manual'), findsNWidgets(3));
      expect(find.textContaining('Overlapping time is counted once.'), findsOneWidget);
      final readingBar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(readingBar.value, closeTo(1 / 60, .00001));
      await tester.ensureVisible(find.text('30 min · Manual').first);
      await tester.tap(find.text('30 min · Manual').first);
      await tester.pumpAndSettle();
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('Correct entry'), findsOneWidget);
      expect(store.readingActivities.every((entry) => entry.seconds == 1800), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('editing a metric previews replacement and retains the original goal', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();
    final goal = ReadingGoal(
      id: 'original',
      type: GoalType.minutes,
      targetValue: 30,
      period: GoalPeriod.daily,
      startDate: now,
      endDate: now.add(const Duration(days: 1)),
      timezone: 'UTC',
    );
    final store = DataStore()..loadData(readingGoals: [goal]);
    final provider = GoalsProvider(watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AddGoalSheet.show(context, provider: provider, editing: goal),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<GoalType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pages read').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('creates a replacement goal'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace goal'));
    await tester.pumpAndSettle();
    expect(store.getReadingGoal('original')!.isArchived, isTrue);
    expect(provider.current.single.goal.type, GoalType.pages);
    expect(tester.takeException(), isNull);
  });
  testWidgets('an unchanged DST deadline remains a target edit rather than a replacement', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 3, 28, 12);
    final end = GoalCalendar.deadline(DateTime(2026, 3, 29), 'Europe/Vilnius');
    final goal = ReadingGoal(
      id: 'deadline',
      type: GoalType.books,
      targetValue: 1,
      period: GoalPeriod.custom,
      startDate: now,
      endDate: end,
      timezone: 'Europe/Vilnius',
      isRecurring: false,
    );
    final store = DataStore()..loadData(readingGoals: [goal]);
    final provider = GoalsProvider(now: () => now, watchClock: false)..attach(store);
    addTearDown(provider.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AddGoalSheet.show(context, provider: provider, editing: goal),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Deadline: 29/3/2026'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Replace goal'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.length, 1);
    expect(store.getReadingGoal('deadline')!.endDate, end);
    expect(store.getReadingGoal('deadline')!.isArchived, isFalse);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(390, 844), const Size(1200, 1000)]) {
    testWidgets('details show a plain scoped summary with activity and live actions at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final now = DateTime.now().toUtc();
      final book = Book(id: 'book', title: 'Alice’s Adventures in Wonderland', author: 'Lewis Carroll', addedAt: now);
      final goal = ReadingGoal(
        id: 'goal',
        type: GoalType.books,
        targetValue: 1,
        period: GoalPeriod.monthly,
        scope: GoalScope.book,
        scopeId: book.id,
        startDate: now.subtract(const Duration(hours: 1)),
        endDate: now.add(const Duration(days: 30)),
      );
      final store = DataStore()..loadData(books: [book], readingGoals: [goal]);
      await store.commitTracking(
        activities: [
          ReadingActivity(
            id: 'finished',
            bookId: book.id,
            bookTitle: book.title,
            kind: 'completion',
            startTime: now.subtract(const Duration(minutes: 5)),
            endTime: now.subtract(const Duration(minutes: 5)),
            createdAt: now,
          ),
        ],
      );
      final provider = GoalsProvider(watchClock: false)..attach(store);
      addTearDown(provider.dispose);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(size.width < 500 ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => GoalDetailsSheet.show(context, goal: goal, provider: provider),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalCard), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Counted activity'), findsNothing);
      expect(find.text('Calendar settings'), findsNothing);
      expect(find.text('Reading activity'), findsOneWidget);
      expect(find.text('Read 1 book this month'), findsOneWidget);
      expect(find.text('1 / 1 book'), findsOneWidget);
      expect(find.text('Target reached'), findsOneWidget);
      expect(find.text('Whole library'), findsNothing);
      expect(find.text(book.title), findsWidgets);
      await tester.ensureVisible(find.text('Pause goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause goal'));
      await tester.pumpAndSettle();
      expect(store.getReadingGoal(goal.id)!.isActive, isFalse);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume goal'), findsOneWidget);
      expect(store.readingActivities, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
      testWidgets('goal sheet footer is above system navigation at $width/${theme.brightness}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 700);
        tester.view.padding = const FakeViewPadding(bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(bottom: 48);
        addTearDown(tester.view.reset);
        final now = DateTime.now().toUtc();
        final goal = ReadingGoal(
          id: 'goal',
          type: GoalType.books,
          targetValue: 12,
          period: GoalPeriod.yearly,
          startDate: DateTime.utc(now.year),
          endDate: DateTime.utc(now.year + 1),
          createdAt: now,
        );
        final store = DataStore()..loadData(readingGoals: [goal]);
        final provider = GoalsProvider(watchClock: false)..attach(store);
        addTearDown(provider.dispose);
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => GoalDetailsSheet.show(context, goal: goal, provider: provider),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final done = find.widgetWithText(FilledButton, 'Done');
        final delete = find.widgetWithText(OutlinedButton, 'Delete');
        expect(done.hitTestable(), findsOneWidget);
        expect(delete.hitTestable(), findsOneWidget);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        expect(tester.getRect(done).bottom, lessThanOrEqualTo(652));
        expect(tester.getRect(delete).top, tester.getRect(done).top);
        expect(find.widgetWithText(OutlinedButton, 'Delete goal'), findsNothing);
        if (width < 600) {
          expect(tester.getSize(delete).width, closeTo(tester.getSize(done).width, 1));
          expect(tester.getSize(find.text('Delete')).height, lessThan(tester.getSize(delete).height));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsNothing);
      });
    }
  }
}
