import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/pages/goals_page.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  Future<void> pumpEmptyGoalsPage(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final dataStore = DataStore()..loadData(readingGoals: const []);
    addTearDown(dataStore.dispose);
    await tester.pumpWidget(createTestPage(page: const GoalsPage(), dataStore: dataStore, screenSize: size));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(400, 800), const Size(1200, 800)]) {
    testWidgets('empty state keeps creation and logging actions available at ${size.width.toInt()}px', (tester) async {
      await pumpEmptyGoalsPage(tester, size);

      final titleCenter = tester.getCenter(find.text('No goals yet'));
      expect(titleCenter.dy, lessThan(size.height / 2));
      expect(find.text('New goal').hitTestable(), findsOneWidget);
      expect(find.text('Log reading').hitTestable(), findsOneWidget);
      expect(find.text('30 minutes daily'), findsOneWidget);
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
    final history = find.byKey(const Key('goal-period-history'));
    await tester.scrollUntilVisible(history, 250, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal history'));
    await tester.pumpAndSettle();
    expect(find.text('Missed'), findsWidgets);
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
        expect(find.text('New goal').hitTestable(), findsOneWidget);
        expect(find.text('Log reading').hitTestable(), findsOneWidget);
        if (size.width > 1000) expect(tester.getSize(find.text('Goals')).width, greaterThan(100));
        expect(find.text('Activity').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Filter dates'), 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Filter dates'));
        await tester.pumpAndSettle();
        expect(find.text('Filter dates').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
