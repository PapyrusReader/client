import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

void main() {
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
