import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';

void main() {
  final fixtures = jsonDecode(File('test/goals/fixtures/projections.json').readAsStringSync()) as List;
  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    test(fixture['name'] as String, () {
      final goal = ReadingGoal.fromJson(fixture['goal'] as Map<String, dynamic>);
      final ledger = (fixture['activities'] as List).map((a) => ReadingActivity.fromJson(a as Map<String, dynamic>));
      final now = DateTime.parse(fixture['now'] as String);
      final totals = projectGoal(goal, ledger, now);
      final expected = fixture['expected'] as Map<String, dynamic>;
      expect(totals.seconds, expected['seconds']);
      expect(totals.pages, closeTo((expected['pages'] as num).toDouble(), .0001));
      expect(totals.finishedBooks, expected['finished_books']);
      expect(totals.days, expected['days']);
      expect(totals.value, expected['current_value']);
    });
  }
  test('Monday weeks and both DST boundaries use calendar days', () {
    final spring = GoalCalendar.calendarPeriod(GoalPeriod.daily, DateTime.utc(2026, 3, 29, 12), 'Europe/Vilnius');
    final autumn = GoalCalendar.calendarPeriod(GoalPeriod.daily, DateTime.utc(2026, 10, 25, 12), 'Europe/Vilnius');
    expect(spring.end.difference(spring.start).inHours, 23);
    expect(autumn.end.difference(autumn.start).inHours, 25);
    final week = GoalCalendar.calendarPeriod(GoalPeriod.weekly, DateTime.utc(2026, 10, 11), 'Europe/Vilnius');
    expect(GoalCalendar.local(week.start, 'Europe/Vilnius').weekday, DateTime.monday);
  });
  test('archiving freezes the current period and stops recurrence', () {
    final at = DateTime.utc(2026, 10, 5, 12);
    final goal = ReadingGoal(
      id: 'goal',
      type: GoalType.minutes,
      targetValue: 30,
      period: GoalPeriod.daily,
      startDate: DateTime.utc(2026, 10, 5),
      endDate: DateTime.utc(2026, 10, 6),
      createdAt: at,
      isRecurring: true,
      isArchived: true,
      isActive: false,
      rules: [GoalRule(at: at, target: 30, active: false, archived: true)],
    );
    expect(GoalCalendar.currentPeriod(goal, DateTime.utc(2026, 11)).start, goal.startDate);
    expect(GoalCalendar.pastPeriods(goal, DateTime.utc(2026, 11)), isEmpty);
  });
  test('checkpoint grouping excludes obscured gaps and retains original IDs', () {
    final start = DateTime.utc(2026, 10, 5);
    ReadingActivity entry(String id, int offset) => ReadingActivity(
      id: id,
      sessionId: 'opening',
      bookId: 'book',
      bookTitle: 'Book',
      source: 'reader',
      startTime: start.add(Duration(seconds: offset)),
      endTime: start.add(Duration(seconds: offset + 10)),
      createdAt: start.add(Duration(seconds: offset + 10)),
    );
    final grouped = groupReadingActivities([entry('a', 0), entry('b', 5), entry('c', 30)]).single;
    expect(grouped.seconds, 25);
    expect(grouped.constituentIds, ['a', 'b', 'c']);
  });
}
