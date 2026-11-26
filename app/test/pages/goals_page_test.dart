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
import 'package:go_router/go_router.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  Future<void> pumpGoalsRouter(WidgetTester tester, DataStore store) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const GoalsPage(),
          routes: [
            GoRoute(
              path: 'history',
              name: 'GOAL_HISTORY',
              builder: (_, state) => GoalsPage.history(goalId: state.uri.queryParameters['goal']),
            ),
          ],
        ),
      ],
    );

    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first-sync failure shows a recoverable offline state on Goals', (tester) async {
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
    repository.snapshots.add(const LibrarySnapshot());
    await tester.pumpAndSettle();
    expect(find.text('Waiting for your library'), findsNothing);
    expect(find.text('No goals pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  void expectSectionsInOrder(WidgetTester tester) {
    final headings = ['In progress', 'Not started', 'Completed', 'Paused'];
    final positions = [
      for (final title in headings) tester.getTopLeft(find.byKey(ValueKey('goal-section-$title'))).dy,
    ];

    expect(positions, orderedEquals([...positions]..sort()));
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
      expectSectionsInOrder(tester);
      expect(find.text('No goals pending'), findsOneWidget);
      expect(find.text('No goals yet'), findsNothing);
      final heading = tester.getRect(find.text('In progress'));
      final message = tester.getRect(find.text('No goals in progress'));
      final icon = tester.getRect(find.byIcon(Icons.auto_stories_outlined));
      expect((icon.left + message.right) / 2, closeTo(heading.center.dx, 1));
      final pageTitle = tester.widget<Text>(find.text('Goals')).style!;
      final sectionTitle = tester.widget<Text>(find.text('In progress')).style!;
      expect(sectionTitle.fontSize!, lessThan(pageTitle.fontSize!));
      expect(find.text('No completed goals yet'), findsOneWidget);
      expect(find.text('No paused goals'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      final history = size.width < Breakpoints.desktopSmall
          ? find.byTooltip('Goal history')
          : find.widgetWithText(TextButton, 'Goal history');
      expect(heading.top, greaterThanOrEqualTo(tester.getRect(history).bottom));
      expect(find.text('Goals').hitTestable(), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(history.hitTestable(), findsOneWidget);

      if (size.width < 840) {
        expect(find.text('Goal history'), findsNothing);
        expect(find.byTooltip('New goal').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Log reading').hitTestable(), findsOneWidget);
        expect(find.text('New goal'), findsNothing);
      } else {
        expect(find.text('New goal').hitTestable(), findsOneWidget);
        expect(find.text('Log reading').hitTestable(), findsOneWidget);
        final create = find.widgetWithText(FilledButton, 'New goal');
        final log = find.widgetWithText(OutlinedButton, 'Log reading');

        expect(
          tester.widget<FilledButton>(create).style!.minimumSize!.resolve({})!.height,
          TouchTargets.desktopRecommended,
        );

        expect(tester.getSize(log).height, TouchTargets.desktopRecommended);
        expect(tester.getSize(create).height, TouchTargets.desktopRecommended);
        expect(tester.getRect(find.text('Goals')).left, heading.left);
        expect(tester.getRect(log).left - tester.getRect(history).right, Spacing.sm);
        expect(find.byType(Divider), findsNothing);
        expect(tester.getRect(create).right, size.width - Spacing.lg);
        expect(find.widgetWithText(LibraryAddButton, 'New goal'), findsOneWidget);
      }

      expect(find.byType(ActionChip), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(size.width < Breakpoints.desktopSmall ? find.byTooltip('New goal') : find.text('New goal'));
      await tester.pumpAndSettle();
      expect(find.text('Books finished'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop sidebar width and large text keep goal actions compact', (tester) async {
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
    expect(find.byTooltip('Goal history').hitTestable(), findsOneWidget);
    expect(find.text('Goals').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('New goal'));
    await tester.pumpAndSettle();
    expect(find.text('Books finished'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile header actions and FAB open their sheets above the safe area', (tester) async {
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
    expect(find.text('Goals').hitTestable(), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(tester.getRect(log).right, greaterThan(340));
    expect(tester.getCenter(log).dy, closeTo(tester.getCenter(find.byTooltip('Goal history')).dy, 1));
    expect(tester.getSize(log).width, lessThanOrEqualTo(48));
    expect(tester.getRect(fab).bottom, lessThanOrEqualTo(812));

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
    expect(tester.takeException(), isNull);
  });

  testWidgets('Goal history keeps recurring periods inspectable on a phone', (tester) async {
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

    await pumpGoalsRouter(tester, store);
    await tester.tap(find.byTooltip('Goal history'));
    await tester.pumpAndSettle();
    expect(find.text('Missed'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Goal history').hitTestable(), findsOneWidget);
    expect(find.text('Missed'), findsNothing);
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

    await pumpGoalsRouter(tester, store);
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
    await tester.tap(find.text('Previous periods'));
    await tester.pumpAndSettle();
    expect(find.text('Goal history'), findsOneWidget);
    expect(find.text('Previous periods'), findsNothing);
    expect(find.byType(GoalCard), findsWidgets);
    expect(find.text('Archived second'), findsNothing);
    await tester.tap(find.byTooltip('Show all goals'));
    await tester.pumpAndSettle();
    expect(find.text('Archived second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history pages below the cards and filters by metric across goals', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 11, 25, 12);

    final store = DataStore()
      ..loadData(
        readingGoals: [
          for (var i = 0; i < 12; i++)
            ReadingGoal(
              id: 'goal-$i',
              title: 'Goal $i',
              type: i < 10 ? GoalType.books : GoalType.pages,
              targetValue: 1,
              period: GoalPeriod.custom,
              startDate: now.subtract(Duration(days: i + 2)),
              endDate: now.subtract(Duration(days: i + 1)),
              isRecurring: false,
              isArchived: i == 11,
            ),
        ],
      );

    addTearDown(store.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(home: GoalsPage.history(now: () => now)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Custom range'), findsOneWidget);
    final scroll = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scroll).position;
    final extent = position.maxScrollExtent;
    expect(extent, greaterThan(0));

    for (final fraction in [0.25, 0.5, 0.75, 1.0, 0.5, 0.0]) {
      position.jumpTo(extent * fraction);
      await tester.pumpAndSettle();
      expect(position.maxScrollExtent, closeTo(extent, 0.01));
    }

    await tester.scrollUntilVisible(find.byTooltip('Next page'), 350, scrollable: scroll);
    expect(
      tester.getTopLeft(find.text('Page 1 of 2')).dy,
      greaterThan(tester.getBottomLeft(find.byType(GoalCard).last).dy),
    );
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Goal 10'), findsOneWidget);
    expect(find.text('Goal 11'), findsOneWidget);
    await tester.tap(find.text('All types').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pages read').last);
    await tester.pumpAndSettle();
    expect(find.byType(GoalCard), findsNWidgets(2));
    expect(find.text('Goal 10'), findsOneWidget);
    expect(find.text('Goal 11'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsNothing);
    expect(find.text('Previous periods'), findsNothing);
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

    expect(find.byTooltip('Goal filters'), findsNothing);
    expect(find.text('Longer-term goals'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.textContaining('Finish confirmation required'), findsNothing);
    await store.commitTracking(activities: [store.reversalFor(completion)]);
    await tester.pumpAndSettle();
    expect(find.text('Achieved'), findsNothing);
    expect(find.text('No completed goals yet'), findsOneWidget);
    expectSectionsInOrder(tester);
    expect(
      find.descendant(of: find.byKey(const ValueKey('goal-section-Completed')), matching: find.byType(GoalCard)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal-section-Not started')),
        matching: find.byKey(const ValueKey('goal-card-Finished target')),
      ),
      findsOneWidget,
    );
    expect(cardIds().take(2), ['Nearly finished', 'Just begun']);
    expect(store.readingActivities.any((entry) => entry.id == completion.id), isTrue);
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

        expect(find.text('Goals').hitTestable(), findsOneWidget);
        final history = size.width < Breakpoints.desktopSmall
            ? find.byTooltip('Goal history')
            : find.text('Goal history');
        expect(history.hitTestable(), findsOneWidget);
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
