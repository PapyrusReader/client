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
import 'package:papyrus/widgets/shared/searchable_book_field.dart';
import 'package:papyrus/widgets/shared/searchable_books_field.dart';

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

  Future<void> showSheet(WidgetTester tester, void Function(BuildContext) show, {ThemeData? theme}) async {
    await size(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.dark,
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

  testWidgets('desktop rows align goal cards without reader launch controls', (tester) async {
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
    expect(find.text('Continue reading'), findsNothing);
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

  testWidgets('goal form uses device timezone without an advanced settings section', (tester) async {
    final store = DataStore()..loadData();
    final goals = provider(store);
    await showSheet(
      tester,
      (context) => AddGoalSheet.show(context, provider: goals, preset: 0, initialTimezone: 'Europe/Vilnius'),
    );
    expect(find.text('Advanced settings'), findsNothing);
    expect(find.byKey(const Key('goal-timezone-button')), findsNothing);
    expect(find.text('Repeat each period'), findsOneWidget);
    expect(
      tester.getTopLeft(find.widgetWithText(TextFormField, 'Name (optional)')).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(DropdownButtonFormField<GoalType>, 'Measure')).dy),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.timezone, 'Europe/Vilnius');
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletion confirms directly from the card menu and preserves activity', (tester) async {
    await size(tester);
    final entry = ReadingActivity(
      id: 'entry',
      bookId: book.id,
      bookTitle: book.title,
      startTime: now,
      endTime: now,
      createdAt: now,
      pages: 5,
    );
    final store = DataStore()..loadData(books: [book], readingGoals: [short]);
    await store.commitTracking(activities: [entry]);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Goal actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalDetailsSheet), findsNothing);
    expect(find.text('Delete goal?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions, hasLength(1));
    await tester.tap(find.byTooltip('Goal actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions, isEmpty);
    expect(store.readingActivities.single.id, entry.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual logging searches books by title author and ISBN before saving', (tester) async {
    final other = Book(id: 'other', title: 'Dune', author: 'Frank Herbert', isbn: '9780441172719', addedAt: now);
    final store = DataStore()..loadData(books: [book, other]);
    final goals = provider(store);
    await showSheet(tester, (context) => LogReadingSheet.show(context, provider: goals));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Session ends at'), findsNothing);
    expect(find.textContaining('Manual entries count'), findsNothing);
    await tester.tap(find.byType(SearchableBookField));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search books');
    for (final query in ['dune', 'herbert', '9780441172719']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Dune'), findsOneWidget);
      expect(find.widgetWithText(ListTile, book.title), findsNothing);
    }
    expect(tester.getRect(find.widgetWithText(ListTile, 'Dune')).bottom, lessThanOrEqualTo(564));
    await tester.tap(find.widgetWithText(ListTile, 'Dune'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes read'), '15');
    await tester.tap(find.widgetWithText(FilledButton, 'Save reading'));
    await tester.pumpAndSettle();
    expect(store.effectiveReadingActivities.single.bookId, other.id);
    expect(store.effectiveReadingActivities.single.seconds, 900);
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

  for (final metric in ['Books finished', 'Pages read', 'Reading time', 'Reading days']) {
    testWidgets('$metric starts with Daily selected', (tester) async {
      final store = DataStore()..loadData();
      final goals = provider(store);
      await showSheet(tester, (context) => AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC'));
      final chooser = find.widgetWithText(ListTile, metric);
      final chooserRoute = ModalRoute.of(tester.element(chooser))!;
      await tester.tap(chooser);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The selector keeps its content while exiting; the form appears only
      // after that route finishes, rather than resizing the current sheet.
      expect(find.byKey(const Key('goal-target-input')), findsNothing);
      expect(chooser, findsOneWidget);
      expect(chooserRoute.animation!.status, AnimationStatus.reverse);
      await tester.pumpAndSettle();
      final formRoute = ModalRoute.of(tester.element(find.byKey(const Key('goal-target-input'))))!;
      expect(formRoute, isNot(same(chooserRoute)));
      expect(chooserRoute.isCurrent, isFalse);
      expect(formRoute.isCurrent, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Daily')).selected, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
      await tester.pumpAndSettle();
      expect(store.goalDefinitions.single.period, GoalPeriod.daily);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('e-ink reopens goal creation without animation', (tester) async {
    final store = DataStore()..loadData();
    final goals = provider(store);
    await showSheet(
      tester,
      (context) => AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC'),
      theme: AppTheme.eink,
    );
    final chooser = find.widgetWithText(ListTile, 'Reading time');
    final chooserRoute = ModalRoute.of(tester.element(chooser))!;
    await tester.tap(chooser);
    await tester.pumpAndSettle();
    final formRoute = ModalRoute.of(tester.element(find.byKey(const Key('goal-target-input'))))!;
    expect(formRoute, isNot(same(chooserRoute)));
    expect(formRoute.transitionDuration, Duration.zero);
    expect(formRoute.reverseTransitionDuration, Duration.zero);
    expect(find.widgetWithText(ListTile, 'Books finished'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the metric chooser does not open a form', (tester) async {
    final store = DataStore()..loadData();
    final goals = provider(store);
    var finished = false;
    await showSheet(tester, (context) {
      AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC').then((_) => finished = true);
    });
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.byKey(const Key('goal-target-input')), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(store.goalDefinitions, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('book selection survives searching and bounds the editable completion target', (tester) async {
    final other = Book(id: 'other', title: 'Dune', author: 'Frank Herbert', addedAt: now);
    final store = DataStore()..loadData(books: [book, other]);
    final goals = provider(store);
    await showSheet(tester, (context) => AddGoalSheet.show(context, provider: goals, initialTimezone: 'UTC'));
    await tester.tap(find.widgetWithText(ListTile, 'Books finished'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<GoalScope>, 'Include'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected books').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SearchableBooksField));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Choose books'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, book.title));
    final search = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search books');
    await tester.enterText(search, 'Herbert');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, book.title), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Dune'));
    await tester.pumpAndSettle();
    final select = find.widgetWithText(FilledButton, 'Select (2)');
    expect(select.hitTestable(), findsOneWidget);
    expect(tester.getRect(select).bottom, lessThanOrEqualTo(564));
    await tester.tap(select);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.physicalSize = const Size(1200, 1100);
    await tester.pumpAndSettle();
    final target = find.byKey(const Key('goal-target-input'));
    await tester.ensureVisible(target);
    expect(tester.widget<TextFormField>(target).controller!.text, '2');
    await tester.enterText(target, '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a target of 1–2.'), findsOneWidget);
    expect(store.goalDefinitions, isEmpty);
    await tester.enterText(target, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.selectedBookIds, ['book', 'other']);
    expect(store.goalDefinitions.single.targetValue, 1);
    expect(store.goalDefinitions.single.period, GoalPeriod.daily);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing keeps the schedule and replaces a goal when a selected book is removed', (tester) async {
    final other = Book(id: 'other', title: 'Dune', author: 'Frank Herbert', addedAt: now);
    final goal = short.copyWith(
      type: GoalType.books,
      targetValue: 2,
      period: GoalPeriod.yearly,
      bookIds: ['book', 'other'],
    );
    final store = DataStore()..loadData(books: [book, other], readingGoals: [goal]);
    final goals = provider(store);
    await showSheet(tester, (context) => AddGoalSheet.show(context, provider: goals, editing: goal));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yearly')).selected, isTrue);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name (optional)'), 'Chosen books');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.id, goal.id);
    expect(store.goalDefinitions.single.selectedBookIds, ['book', 'other']);
    final updated = store.goalDefinitions.single;
    await showSheet(tester, (context) => AddGoalSheet.show(context, provider: goals, editing: updated));
    final chip = find.widgetWithText(Chip, 'Dune');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.cancel)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('goal-target-input'))).controller!.text, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Replace goal'));
    await tester.pumpAndSettle();
    expect(store.getReadingGoal(goal.id)!.isArchived, isTrue);
    expect(store.getReadingGoal(goal.id)!.selectedBookIds, ['book', 'other']);
    expect(goals.current.single.goal.selectedBookIds, ['book']);
    expect(goals.current.single.goal.targetValue, 1);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('What would you like to track?'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Pages read'));
    await tester.pumpAndSettle();
    final target = find.byKey(const Key('goal-target-input'));
    await tester.enterText(target, '73');
    expect(find.byTooltip('Increase target'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Monthly'));
    await tester.pump();
    await tester.tap(find.text('Repeat each period'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create goal'));
    await tester.pumpAndSettle();
    expect(store.goalDefinitions.single.targetValue, 73);
    expect(store.goalDefinitions.single.isRecurring, isFalse);
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
