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

      final ledger = (fixture['activities'] as List).map(
        (item) => ReadingActivity.fromJson(item as Map<String, dynamic>),
      );

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

  test('eligible activity durations preserve originals and merge grouped checkpoints', () {
    final fixture = fixtures.last as Map<String, dynamic>;
    final goal = ReadingGoal.fromJson(fixture['goal'] as Map<String, dynamic>);

    final ledger = (fixture['activities'] as List)
        .map((item) => ReadingActivity.fromJson(item as Map<String, dynamic>))
        .toList();

    final progress = projectGoal(goal, ledger, DateTime.parse(fixture['now'] as String));
    expect(progress.hasCreationCutoff, isTrue);
    expect(progress.hasOverlappingTime, isTrue);
    expect(progress.fraction, closeTo(1 / 60, .00001));

    for (final activity in progress.activities) {
      expect(progress.eligibleSecondsFor(activity), 30);
      expect(activity.seconds, 1800);
      expect(activity.toJson(), ledger.firstWhere((entry) => entry.id == activity.id).toJson());
    }

    final reader = ledger
        .map(
          (entry) => ReadingActivity(
            id: entry.id,
            bookId: entry.bookId,
            bookTitle: entry.bookTitle,
            startTime: entry.startTime,
            endTime: entry.endTime,
            createdAt: entry.createdAt,
            source: 'reader',
            sessionId: 'session',
          ),
        )
        .toList();

    final readerProgress = projectGoal(goal, reader, DateTime.parse(fixture['now'] as String));
    final grouped = groupReadingActivities(readerProgress.activities).single;
    expect(grouped.seconds, 1800);
    expect(readerProgress.eligibleSecondsFor(grouped), 30);
    final olderGoal = goal.copyWith(createdAt: DateTime.utc(2026, 10, 5));
    final fullProgress = projectGoal(olderGoal, ledger, DateTime.parse(fixture['now'] as String));
    expect(fullProgress.seconds, 1800);
    expect(fullProgress.hasCreationCutoff, isFalse);
    expect(fullProgress.hasOverlappingTime, isTrue);
  });

  test('separate manual sessions add normally and partial pauses stay excluded', () {
    final start = DateTime.utc(2026, 10, 8, 10);

    final goal = ReadingGoal(
      id: 'goal',
      type: GoalType.minutes,
      targetValue: 90,
      period: GoalPeriod.daily,
      startDate: start,
      endDate: start.add(const Duration(days: 1)),
      createdAt: start,
    );

    final sessions = [
      for (var i = 0; i < 3; i++)
        ReadingActivity(
          id: 'session-$i',
          bookId: 'book',
          bookTitle: 'Book',
          startTime: start.add(Duration(minutes: 30 * i)),
          endTime: start.add(Duration(minutes: 30 * (i + 1))),
          createdAt: start,
        ),
    ];

    final progress = projectGoal(goal, sessions, start.add(const Duration(hours: 2)));
    expect(progress.seconds, 5400);
    expect(progress.reached, isTrue);
    expect(progress.hasOverlappingTime, isFalse);
    expect(progress.hasCreationCutoff, isFalse);

    final paused = goal.copyWith(
      rules: [
        GoalRule(at: start, target: 90),
        GoalRule(at: start.add(const Duration(minutes: 10)), target: 90, active: false),
        GoalRule(at: start.add(const Duration(minutes: 20)), target: 90),
      ],
    );

    final partial = projectGoal(paused, sessions, start.add(const Duration(hours: 2)));
    expect(partial.seconds, 4800);
    expect(partial.eligibleSecondsFor(sessions.first), 1200);
    expect(partial.eligibleSecondsFor(sessions.last), 1800);
    expect(partial.hasOverlappingTime, isFalse);
  });

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
