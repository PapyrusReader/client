import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

void main() {
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
    expect(find.textContaining('starts a replacement goal'), findsOneWidget);
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
        final delete = find.widgetWithText(OutlinedButton, 'Delete goal');
        expect(done.hitTestable(), findsOneWidget);
        expect(delete.hitTestable(), findsOneWidget);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        expect(tester.getRect(done).bottom, lessThanOrEqualTo(652));
        expect(tester.getRect(delete).top, tester.getRect(done).top);
        expect(tester.takeException(), isNull);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsNothing);
      });
    }
  }
}
