import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/active_goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/completed_goal_chip.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

void main() {
  final goal = ReadingGoal(
    id: 'goal',
    type: GoalType.books,
    targetValue: 12,
    currentValue: 4,
    period: GoalPeriod.yearly,
    startDate: DateTime(2026),
    endDate: DateTime(2026, 12, 31),
  );

  Future<void> openSheet(WidgetTester tester, {required bool completed, double width = 390}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                if (completed) {
                  CompletedGoalChip.showDetailsSheet(context, goal: goal);
                } else {
                  ActiveGoalDetailsSheet.show(context, goal: goal);
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final completed in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('${completed ? 'completed' : 'active'} goal actions fit above system navigation at $width', (
        tester,
      ) async {
        await openSheet(tester, completed: completed, width: width);
        final done = find.widgetWithText(FilledButton, 'Done');
        final delete = find.widgetWithText(OutlinedButton, completed ? 'Delete goal' : 'Delete');
        expect(done.hitTestable(), findsOneWidget);
        expect(delete.hitTestable(), findsOneWidget);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        expect(tester.getRect(done).bottom, lessThanOrEqualTo(652));
        expect(tester.getRect(delete).top, tester.getRect(done).top);
        expect(tester.getRect(delete).height, tester.getRect(done).height);
        expect(tester.takeException(), isNull);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsNothing);
      });
    }

    testWidgets('${completed ? 'completed' : 'active'} goal header closes the sheet', (tester) async {
      await openSheet(tester, completed: completed);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheet), findsNothing);
    });
  }
}
