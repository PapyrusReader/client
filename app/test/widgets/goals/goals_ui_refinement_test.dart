import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/pages/goals_page.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/goals/reading_activity_heatmap.dart';
import 'package:papyrus/widgets/goals/reading_activity_timeline.dart';

void main() {
  final now = DateTime.now().toUtc();
  final book = Book(
    id: 'book',
    title: 'A very long book title that would otherwise wrap across several lines in the scope label',
    author: '',
    addedAt: now,
  );
  final short = ReadingGoal(
    id: 'short',
    type: GoalType.minutes,
    targetValue: 30,
    period: GoalPeriod.daily,
    scope: GoalScope.book,
    scopeId: book.id,
    startDate: now,
    endDate: now.add(const Duration(days: 1)),
  );
  final days = ReadingGoal(
    id: 'days',
    type: GoalType.days,
    targetValue: 5,
    period: GoalPeriod.weekly,
    startDate: now,
    endDate: now.add(const Duration(days: 7)),
  );

  Future<void> size(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1100);
    addTearDown(tester.view.reset);
  }

  Future<void> showSheet(WidgetTester tester, void Function(BuildContext) show) async {
    await size(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => show(context), child: const Text('Open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  GoalsProvider provider(DataStore store) {
    addTearDown(store.dispose);
    final value = GoalsProvider(watchClock: false)..attach(store);
    addTearDown(value.dispose);
    return value;
  }

  testWidgets('desktop rows align mixed goal cards and their reading actions', (tester) async {
    final semantics = tester.ensureSemantics();
    await size(tester);
    final store = DataStore()..loadData(books: [book], readingGoals: [short, days]);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final left = tester.getRect(find.byKey(const ValueKey('goal-card-short')));
    final right = tester.getRect(find.byKey(const ValueKey('goal-card-days')));
    expect(left.height, right.height);
    expect(find.bySemanticsLabel('Continue reading'), findsNWidgets(2));
    semantics.dispose();
    final actions = find.widgetWithText(TextButton, 'Continue reading');
    expect(tester.getRect(actions.at(0)).bottom, tester.getRect(actions.at(1)).bottom);
    final log = find.widgetWithText(OutlinedButton, 'Log reading');
    expect(tester.getSize(log).width, lessThan(300));
    final theme = Theme.of(tester.element(log));
    expect(theme.outlinedButtonTheme.style!.shape!.resolve({}), isA<StadiumBorder>());
    expect(theme.filledButtonTheme.style!.shape!.resolve({}), isA<StadiumBorder>());
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Filter dates')).width, lessThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal sheet actions stay content sized on a wide screen', (tester) async {
    final store = DataStore()..loadData(readingGoals: [short]);
    final goals = provider(store);
    await showSheet(tester, (context) => GoalDetailsSheet.show(context, goal: short, provider: goals));
    for (final label in ['Edit goal', 'Pause goal', 'Archive goal']) {
      expect(tester.getSize(find.widgetWithText(OutlinedButton, label)).width, lessThan(300));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual date time and numeric controls have compact widths', (tester) async {
    final store = DataStore()..loadData(books: [book]);
    final goals = provider(store);
    await showSheet(tester, (context) => LogReadingSheet.show(context, provider: goals, book: book));
    for (final icon in [Icons.event_outlined, Icons.schedule]) {
      expect(tester.getSize(find.widgetWithIcon(OutlinedButton, icon)).width, lessThan(300));
    }
    for (final label in ['Minutes read', 'Pages read']) {
      expect(
        tester.getSize(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label)).width,
        lessThanOrEqualTo(220),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('timezone is advanced, searchable, selectable and saved as an IANA identifier', (tester) async {
    final store = DataStore()..loadData();
    final goals = provider(store);
    await showSheet(
      tester,
      (context) => AddGoalSheet.show(context, provider: goals, preset: 0, initialTimezone: 'UTC'),
    );
    expect(find.byKey(const Key('goal-timezone-button')).hitTestable(), findsNothing);
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Timezone'), findsNothing);
    await tester.tap(find.text('Advanced settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-timezone-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Search city or timezone'),
      'Vilnius',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Vilnius'));
    await tester.pumpAndSettle();
    expect(find.text('Timezone: Vilnius'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.timezone, 'Europe/Vilnius');
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('metric chooser and simple form remain usable on a small phone at ${scale}x', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      tester.view.padding = const FakeViewPadding(bottom: 40);
      tester.view.viewPadding = const FakeViewPadding(bottom: 40);
      addTearDown(tester.view.reset);
      final store = DataStore()..loadData();
      final goals = provider(store);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      expect(cancel.hitTestable(), findsOneWidget);
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(680));
      final metric = find.widgetWithText(ListTile, 'Reading days');
      await tester.ensureVisible(metric);
      await tester.pumpAndSettle();
      await tester.tap(metric);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Create goal');
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(680));
      final target = find.byKey(const Key('goal-target-input'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.enterText(target, '6');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.goalDefinitions.single.targetValue, 6);
      expect(store.goalDefinitions.single.type, GoalType.days);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('goal targets and deadline controls stay bounded', (tester) async {
    final store = DataStore()..loadData(books: [book]);
    final goals = provider(store);
    await showSheet(
      tester,
      (context) => AddGoalSheet.show(context, provider: goals, preset: 4, initialTimezone: 'UTC'),
    );
    final target = find.byWidgetPredicate((w) => w is TextFormField && w.key == const Key('goal-target-input'));
    expect(tester.getSize(target).width, lessThanOrEqualTo(220));
    expect(tester.getSize(find.widgetWithIcon(OutlinedButton, Icons.event_outlined)).width, lessThan(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric first creation has an editable target and saves the chosen schedule', (tester) async {
    final store = DataStore()..loadData();
    final goals = provider(store);
    await showSheet(tester, (context) => AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC'));
    expect(find.text('What would you like to track?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Pages read'));
    await tester.pumpAndSettle();
    final target = find.byKey(const Key('goal-target-input'));
    await tester.enterText(target, '73');
    await tester.tap(find.byTooltip('Increase target'));
    await tester.pump();
    expect(find.text('74'), findsOneWidget);
    await tester.tap(find.byTooltip('Decrease target'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Monthly'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.targetValue, 73);
    expect(store.goalDefinitions.single.period, GoalPeriod.monthly);
    expect(store.goalDefinitions.single.type, GoalType.pages);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets('year heatmap uses the whole available width and dates are selectable at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      final date = DateTime.utc(2026, 10, 7);
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.eink,
          home: Scaffold(
            body: ReadingActivityHeatmap(
              activities: [
                ReadingActivity(
                  id: 'pages',
                  bookId: 'book',
                  bookTitle: 'Book',
                  startTime: date,
                  endTime: date,
                  createdAt: date,
                  pages: 10,
                ),
              ],
              year: 2026,
              timezone: 'UTC',
              now: date,
              onYearChanged: (_) {},
              onDaySelected: (day) => selected = day,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('reading-activity-heatmap'))).width, width);
      expect(find.text('1 active day'), findsOneWidget);
      final today = find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Oct 7, 2026: Reading logged');
      await tester.ensureVisible(today);
      await tester.tap(today);
      await tester.pump();
      expect(selected, date);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('heatmap weekday labels fit their rows with large e-ink text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ReadingActivityHeatmap(
            activities: const [],
            year: 2026,
            timezone: 'UTC',
            now: DateTime.utc(2026, 10, 7),
            onYearChanged: (_) {},
            onDaySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cell = find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Oct 7, 2026: No reading');
    expect(tester.getSize(find.text('M')).height, lessThanOrEqualTo(tester.getSize(cell).height + 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline summarizes raw intervals without gaps and keeps entry inspection', (tester) async {
    await size(tester);
    final store = DataStore()..loadData(books: [book]);
    final goals = provider(store);
    final date = now.subtract(const Duration(minutes: 10));
    final entries = [
      for (var i = 0; i < 2; i++)
        ReadingActivity(
          id: 'checkpoint-$i',
          sessionId: 'same-opening',
          bookId: book.id,
          bookTitle: book.title,
          source: 'reader',
          startTime: date.add(Duration(minutes: i * 3)),
          endTime: date.add(Duration(minutes: i * 3 + 1)),
          createdAt: now,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReadingActivityTimeline(activities: entries, provider: goals, timezone: 'UTC'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(book.title), findsOneWidget);
    expect(find.text('2m · Reader'), findsOneWidget);
    await tester.tap(find.text(book.title));
    await tester.pumpAndSettle();
    expect(find.text(book.title), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '2 min · Reader').last);
    await tester.pumpAndSettle();
    expect(find.text('Undo this entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity groups repeated titles while preserving individual entries and audit actions', (tester) async {
    await size(tester);
    final store = DataStore()..loadData(books: [book]);
    final goals = provider(store);
    final entries = [
      for (var i = 0; i < 3; i++)
        ReadingActivity(
          id: '$i',
          bookId: book.id,
          bookTitle: book.title,
          startTime: now.subtract(Duration(minutes: i + 1)),
          endTime: now,
          createdAt: now,
          source: i == 2 ? 'manual' : 'reader',
          pages: i == 2 ? 10 : 0,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReadingActivityList(activities: entries, provider: goals, correctedIds: const {'1'}),
        ),
      ),
    );
    expect(find.text(book.title), findsOneWidget);
    expect(find.text('1 min · Reader'), findsOneWidget);
    expect(find.text('2 min · Reader · Corrected'), findsOneWidget);
    await tester.tap(find.text('1 min · Reader'));
    await tester.pumpAndSettle();
    expect(find.text('Undo this entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
