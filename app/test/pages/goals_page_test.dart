import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/pages/goals_page.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/book_details/book_details_tab_rail.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  testWidgets('first-sync failure shows a recoverable offline state on both tabs', (tester) async {
    final repository = _LoadingLibraryRepository();
    final store = DataStore(bookRepository: repository);
    addTearDown(store.dispose);
    addTearDown(repository.snapshots.close);
    await tester.pumpWidget(createTestPage(page: const GoalsPage(), dataStore: store));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    repository.snapshots.add(LibrarySnapshot(isLoaded: false, loadError: StateError('Connection unavailable')));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Waiting for your library').hitTestable(), findsOneWidget);
    expect(find.text('Your reading goals will appear when the connection is restored.').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for your library').hitTestable(), findsOneWidget);
    repository.snapshots.add(const LibrarySnapshot());
    await tester.pumpAndSettle();
    expect(find.text('Waiting for your library'), findsNothing);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('No goals yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> toggleCompleted(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Goal filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<bool>));
    await tester.pumpAndSettle();
  }

  Future<void> pumpEmptyGoalsPage(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final dataStore = DataStore()..loadData(readingGoals: const []);
    addTearDown(dataStore.dispose);
    await tester.pumpWidget(createTestPage(page: const GoalsPage(), dataStore: dataStore, screenSize: size));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(400, 800), const Size(1200, 800), const Size(1600, 800)]) {
    testWidgets('empty state keeps creation and logging actions available at ${size.width.toInt()}px', (tester) async {
      await pumpEmptyGoalsPage(tester, size);
      final placeholder = find.byKey(const Key('goals-empty-state'));
      final viewport = tester.getRect(find.byType(TabBarView));
      expect(tester.getRect(placeholder), viewport);
      final iconTop = tester.getRect(find.byIcon(Icons.emoji_events_outlined)).top;

      final actionBottom = tester
          .getRect(find.descendant(of: placeholder, matching: find.byType(EmptyStateAction)))
          .bottom;

      expect((iconTop + actionBottom) / 2, closeTo(viewport.center.dy, 1));
      expect(find.text('Goals'), findsNothing);
      // Only the tab divider remains; there is no separate header border.
      expect(find.byType(Divider), findsOneWidget);

      const referenceRail = BookDetailsTabRail(
        tabs: [
          Tab(text: 'Details'),
          Tab(text: 'Notes'),
        ],
      );

      expect(tester.getSize(find.byType(TabBar)).height, referenceRail.preferredSize.height);

      expect(
        tester.getRect(find.byType(TabBar)).top,
        libraryPageHorizontalPadding(tester.element(find.byType(TabBar))),
      );

      if (size.width < 840) {
        expect(find.byTooltip('New goal').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Log reading').hitTestable(), findsOneWidget);
        expect(find.text('New goal').hitTestable(), findsWidgets);
      } else {
        expect(find.text('New goal').hitTestable(), findsWidgets);
        expect(find.text('Log reading').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.widgetWithText(OutlinedButton, 'Log reading')).top, Spacing.lg);
        final create = find.widgetWithText(FilledButton, 'New goal').first;
        expect(tester.getRect(create).top, Spacing.lg);
        final log = find.widgetWithText(OutlinedButton, 'Log reading');

        expect(
          tester.widget<FilledButton>(create).style!.minimumSize!.resolve({})!.height,
          TouchTargets.desktopRecommended,
        );

        expect(tester.getSize(log).height, TouchTargets.desktopRecommended);
        expect(tester.getSize(create).height, TouchTargets.desktopRecommended);
        final divider = tester.getRect(find.byType(Divider));
        // Measure the painted surfaces, rather than treating the touch target as the border.
        final createSurface = find.descendant(of: create, matching: find.byType(Material)).first;
        final logSurface = find.descendant(of: log, matching: find.byType(Material)).first;
        expect(divider.top - tester.getRect(createSurface).bottom, greaterThanOrEqualTo(Spacing.sm));
        expect(divider.top - tester.getRect(logSurface).bottom, greaterThanOrEqualTo(Spacing.sm));
        expect(divider.left, Spacing.lg);
        expect(size.width - divider.right, Spacing.lg);
        expect(tester.getRect(create).right, size.width - Spacing.lg);
        expect(find.widgetWithText(LibraryAddButton, 'New goal'), findsOneWidget);
      }

      expect(find.byType(ActionChip), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Create a goal to track your reading progress.'), findsOneWidget);
      await tester.tap(find.descendant(of: placeholder, matching: find.byType(EmptyStateAction)));
      await tester.pumpAndSettle();
      expect(find.text('Books finished'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop sidebar width and large text keep tab actions compact', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);
    final store = DataStore()..loadData(readingGoals: const []);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Align(child: SizedBox(width: 560, child: GoalsPage())),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Log reading').hitTestable(), findsOneWidget);
    expect(find.byTooltip('New goal').hitTestable(), findsOneWidget);
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    expect(find.text('Activity').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('New goal'));
    await tester.pumpAndSettle();
    expect(find.text('Books finished'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile header actions and FAB open their sheets on both tabs above the safe area', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 32);
    tester.view.viewPadding = const FakeViewPadding(bottom: 32);
    addTearDown(tester.view.reset);
    final store = DataStore()..loadData(readingGoals: const []);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );

    await tester.pumpAndSettle();
    final log = find.byTooltip('Log reading');
    final fab = find.byTooltip('New goal');
    expect(find.text('Goals'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.getRect(log).right, greaterThan(340));
    expect(tester.getCenter(log).dy, closeTo(tester.getCenter(find.text('Overview')).dy, 1));
    expect(tester.getSize(log).width, lessThanOrEqualTo(48));
    expect(tester.getRect(fab).bottom, lessThanOrEqualTo(812));

    for (final tab in ['Overview', 'Activity']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('Books finished'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(log);
      await tester.pumpAndSettle();
      expect(find.text('Save reading'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.dark, AppTheme.light, AppTheme.eink]) {
    testWidgets('goal tabs swipe both ways and retain activity scroll in ${theme.brightness}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final store = DataStore()..loadData(readingGoals: const []);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(theme: theme, home: const GoalsPage()),
        ),
      );

      await tester.pumpAndSettle();
      final pages = find.byType(TabBarView);
      final controller = tester.widget<TabBarView>(pages).controller!;
      expect(controller.index, 0);
      await tester.drag(pages, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(find.text('No goals yet'), findsNothing);

      final activityScroll = find
          .descendant(of: find.byKey(const PageStorageKey('goals-activity-scroll')), matching: find.byType(Scrollable))
          .first;

      await tester.scrollUntilVisible(find.text('Filter dates'), 180, scrollable: activityScroll);
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(activityScroll).position.pixels;
      expect(offset, greaterThan(0));
      await tester.drag(pages, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      expect(find.text('No goals yet'), findsOneWidget);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(tester.state<ScrollableState>(activityScroll).position.pixels, closeTo(offset, 1));
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('activity keeps recurring goal periods inspectable on a phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();

    final store = DataStore()
      ..loadData(
        readingGoals: [
          ReadingGoal(
            id: 'recurring',
            type: GoalType.minutes,
            targetValue: 30,
            period: GoalPeriod.daily,
            startDate: now.subtract(const Duration(days: 3)),
            endDate: now.subtract(const Duration(days: 2)),
          ),
        ],
      );

    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    final history = find.byKey(const PageStorageKey('goal-period-history'));

    await tester.scrollUntilVisible(
      history,
      250,
      scrollable: find
          .descendant(of: find.byKey(const PageStorageKey('goals-activity-scroll')), matching: find.byType(Scrollable))
          .first,
    );

    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal history'));
    await tester.pumpAndSettle();
    expect(find.text('Missed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived goals appear once below their heading with periods available in details', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();

    final store = DataStore()
      ..loadData(
        readingGoals: [
          for (final id in ['first', 'second'])
            ReadingGoal(
              id: id,
              title: 'Archived $id',
              type: GoalType.books,
              targetValue: 1,
              period: GoalPeriod.daily,
              createdAt: now.subtract(const Duration(days: 3)),
              startDate: now.subtract(const Duration(days: 3)),
              endDate: now.subtract(const Duration(days: 2)),
              isActive: false,
              isArchived: true,
            ),
        ],
      );

    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal history'));
    await tester.pumpAndSettle();
    final heading = tester.getRect(find.text('Archived goals'));
    expect(find.byType(GoalCard), findsNWidgets(2));

    for (final id in ['first', 'second']) {
      expect(find.text('Archived $id'), findsOneWidget);
      expect(tester.getRect(find.text('Archived $id')).top, greaterThan(heading.bottom));
    }

    await tester.tap(find.text('Archived first'));
    await tester.pumpAndSettle();
    expect(find.text('Previous periods'), findsOneWidget);
    expect(find.text('Restore goal'), findsOneWidget);
    expect(find.textContaining('Missed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived goal activity restores scroll and expansion independently', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final now = DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 12);

    final store = DataStore()
      ..loadData(
        readingGoals: [
          ReadingGoal(
            id: 'archived',
            title: 'Archived reading goal',
            type: GoalType.minutes,
            targetValue: 30,
            period: GoalPeriod.daily,
            createdAt: now.subtract(const Duration(hours: 1)),
            startDate: now.subtract(const Duration(hours: 1)),
            endDate: now.add(const Duration(days: 1)),
            isActive: false,
            isArchived: true,
          ),
        ],
      );

    await store.commitTracking(
      activities: [
        ReadingActivity(
          id: 'manual',
          bookId: 'alice',
          bookTitle: 'Alice',
          startTime: now.subtract(const Duration(minutes: 10)),
          endTime: now,
          createdAt: now,
        ),
      ],
    );

    addTearDown(store.dispose);
    final bucket = PageStorageBucket();

    Future<void> openPage(int revision) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: PageStorage(
              bucket: bucket,
              child: GoalsPage(key: ValueKey(revision)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
    }

    await openPage(0);
    final scrollKey = find.byKey(const PageStorageKey('goals-activity-scroll'));
    // Mimic the saved zero offset from the web failure. Expansion rows must
    // never read a numeric scroll offset as their boolean state.
    bucket.writeState(tester.element(scrollKey), 0.0);
    await openPage(1);
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(of: scrollKey, matching: find.byType(Scrollable)).first;
    final bookRow = find.widgetWithText(ExpansionTile, 'Alice');
    await tester.scrollUntilVisible(bookRow, 200, scrollable: scrollable);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    final history = find.widgetWithText(ExpansionTile, 'Goal history');
    await tester.scrollUntilVisible(history, 200, scrollable: scrollable);
    await tester.ensureVisible(history);
    await tester.tap(find.text('Goal history'));
    await tester.pumpAndSettle();
    expect(find.text('Archived goals'), findsOneWidget);
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));
    await openPage(2);
    expect(tester.takeException(), isNull);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, closeTo(offset, 1));
    expect(find.text('Archived goals'), findsOneWidget);
    await tester.scrollUntilVisible(bookRow, -200, scrollable: scrollable);
    expect(find.textContaining('10 min'), findsWidgets);
    final tile = tester.widget<ExpansionTile>(bookRow);
    final expandedChild = find.byWidget(tile.children.first);
    expect(expandedChild.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview ranks real progress across schedules and updates after undo', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    // Keep the full reading interval in one day, regardless of when CI runs.
    final now = DateTime.utc(2026, 10, 8, 12);
    final created = now.subtract(const Duration(hours: 1));
    final book = Book(id: 'alice', title: 'Alice', author: 'Lewis Carroll', addedAt: created);

    ReadingGoal goal(String id, GoalType type, int target, GoalPeriod period, {bool active = true}) => ReadingGoal(
      id: id,
      title: id,
      type: type,
      targetValue: target,
      period: period,
      startDate: created,
      endDate: now.add(const Duration(days: 365)),
      createdAt: created,
      timezone: 'UTC',
      isActive: active,
      minimumMinutes: 20,
      scope: GoalScope.book,
      scopeId: book.id,
    );

    final store = DataStore()
      ..loadData(
        books: [book],
        readingGoals: [
          goal('Books halfway', GoalType.books, 2, GoalPeriod.yearly),
          goal('Not started yet', GoalType.days, 5, GoalPeriod.weekly),
          goal('Nearly finished', GoalType.minutes, 20, GoalPeriod.daily),
          goal('Finished target', GoalType.books, 1, GoalPeriod.monthly),
          goal('On hold', GoalType.pages, 100, GoalPeriod.weekly, active: false),
          goal('Just begun', GoalType.minutes, 100, GoalPeriod.weekly),
        ],
      );

    addTearDown(store.dispose);

    final completion = ReadingActivity(
      id: 'finished',
      bookId: book.id,
      bookTitle: book.title,
      kind: 'completion',
      startTime: now,
      endTime: now,
      createdAt: now,
    );

    await store.commitTracking(
      activities: [
        completion,
        ReadingActivity(
          id: 'reading',
          bookId: book.id,
          bookTitle: book.title,
          startTime: now.subtract(const Duration(minutes: 15)),
          endTime: now,
          createdAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: GoalsPage(now: () => now),
        ),
      ),
    );

    await tester.pumpAndSettle();
    List<String> cardIds() => tester.widgetList<GoalCard>(find.byType(GoalCard)).map((card) => card.goal.id).toList();

    // Reading days require 20 minutes so this period has not qualified yet.
    expect(cardIds(), [
      'Nearly finished',
      'Books halfway',
      'Just begun',
      'Not started yet',
      'Finished target',
      'On hold',
    ]);

    for (final label in ['In progress', 'Not started', 'Completed', 'Paused']) {
      expect(find.text(label), findsWidgets);
    }

    expect(find.text('Longer-term goals'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.textContaining('Finish confirmation required'), findsNothing);
    await toggleCompleted(tester);
    expect(cardIds(), isNot(contains('Finished target')));
    expect(cardIds(), contains('On hold'));
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(cardIds(), isNot(contains('Finished target')));
    await toggleCompleted(tester);
    expect(cardIds(), contains('Finished target'));
    await store.commitTracking(activities: [store.reversalFor(completion)]);
    await tester.pumpAndSettle();
    expect(find.text('Achieved'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(cardIds().take(2), ['Nearly finished', 'Just begun']);
    expect(store.readingActivities.any((entry) => entry.id == completion.id), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding the only completed goal keeps the filter and creation action available', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();

    final goal = ReadingGoal(
      id: 'done',
      type: GoalType.books,
      targetValue: 1,
      period: GoalPeriod.daily,
      startDate: now.subtract(const Duration(hours: 1)),
      endDate: now.add(const Duration(days: 1)),
    );

    final store = DataStore()..loadData(readingGoals: [goal]);
    addTearDown(store.dispose);

    await store.commitTracking(
      activities: [
        ReadingActivity(
          id: 'finished',
          bookId: 'book',
          bookTitle: 'Book',
          kind: 'completion',
          startTime: now,
          endTime: now,
          createdAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.getCenter(find.byTooltip('Goal filters')).dy, closeTo(tester.getCenter(find.text('Overview')).dy, 1));
    await toggleCompleted(tester);
    expect(find.byType(GoalCard), findsNothing);
    expect(find.text('No goals yet'), findsNothing);
    expect(find.text('All goals completed'), findsOneWidget);
    expect(find.byTooltip('Goal filters').hitTestable(), findsOneWidget);
    expect(find.byTooltip('New goal').hitTestable(), findsOneWidget);
    await toggleCompleted(tester);
    expect(find.byType(GoalCard), findsOneWidget);
    expect(find.text('All goals completed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    for (final size in [const Size(320, 720), const Size(768, 1024), const Size(1440, 1000)]) {
      testWidgets('active Goals supports large text at $size in ${theme.brightness}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final now = DateTime.now().toUtc();

        final store = DataStore()
          ..loadData(
            readingGoals: [
              ReadingGoal(
                id: 'daily',
                type: GoalType.minutes,
                targetValue: 30,
                period: GoalPeriod.daily,
                createdAt: now,
                startDate: now,
                endDate: now.add(const Duration(days: 1)),
              ),
              ReadingGoal(
                id: 'yearly',
                type: GoalType.books,
                targetValue: 12,
                period: GoalPeriod.yearly,
                createdAt: now,
                startDate: now,
                endDate: now.add(const Duration(days: 365)),
              ),
            ],
          );

        addTearDown(store.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: store,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(size.width == 320 ? 2 : 1)),
                child: child!,
              ),
              home: const GoalsPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        if (size.width < 840) {
          expect(find.byTooltip('New goal').hitTestable(), findsOneWidget);
          expect(find.byTooltip('Log reading').hitTestable(), findsOneWidget);
        } else {
          expect(find.text('New goal').hitTestable(), findsOneWidget);
          expect(find.text('Log reading').hitTestable(), findsOneWidget);
        }

        expect(find.text('Goals'), findsNothing);
        expect(find.text('Activity').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Filter dates'),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('goals-activity-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );

        await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Filter dates'));
        await tester.pumpAndSettle();
        expect(find.text('Filter dates').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _LoadingLibraryRepository extends InMemoryBookRepository implements LibraryRepository {
  final snapshots = StreamController<LibrarySnapshot>();

  @override
  Stream<LibrarySnapshot> watchLibrary() => snapshots.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
