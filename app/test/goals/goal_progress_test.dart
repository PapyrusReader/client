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

  test('each goal lists the entries credited to its metric on the credited day', () {
    final firstDay = DateTime.utc(2026, 10, 8);
    final secondDay = DateTime.utc(2026, 10, 9);
    final end = DateTime.utc(2026, 10, 10);

    final goal = ReadingGoal(
      id: 'goal',
      type: GoalType.pages,
      targetValue: 10,
      period: GoalPeriod.custom,
      startDate: firstDay,
      createdAt: firstDay,
      endDate: end,
      timezone: 'UTC',
    );

    ReadingActivity entry(
      String id,
      DateTime at, {
      int seconds = 0,
      int pages = 0,
      double? extent,
      String kind = 'reading',
    }) => ReadingActivity(
      id: id,
      bookId: 'book',
      bookTitle: 'Book',
      startTime: at.subtract(Duration(seconds: seconds)),
      endTime: at,
      createdAt: at,
      pages: pages,
      kind: kind,
      coverage: [
        if (extent != null) PageCoverage(key: 'chapter', start: 0, end: extent, pagesPerUnit: 1, estimated: true),
      ],
    );

    final ledger = [
      entry('time-only', firstDay.add(const Duration(minutes: 2)), seconds: 10),
      entry('cross-midnight', secondDay.add(const Duration(minutes: 5)), seconds: 360, extent: .25),
      entry('repeat', secondDay.add(const Duration(minutes: 6)), extent: .25),
      entry('extended', secondDay.add(const Duration(minutes: 7)), extent: .5),
      entry('manual-pages', secondDay.add(const Duration(minutes: 8)), pages: 2),
      entry('finished', secondDay.add(const Duration(minutes: 9)), kind: 'completion'),
      entry('finished-again', secondDay.add(const Duration(minutes: 10)), kind: 'completion'),
    ];

    Map<DateTime, List<String>> contributions(GoalType type) {
      final progress = projectGoal(goal.copyWith(type: type), ledger, end, collectContributions: true);
      return progress.contributionsByDay.map(
        (day, entries) => MapEntry(day, entries.map((entry) => entry.id).toList()),
      );
    }

    expect(contributions(GoalType.pages), {
      secondDay: ['cross-midnight', 'extended', 'manual-pages'],
    });
    expect(contributions(GoalType.books), {
      secondDay: ['finished'],
    });
    expect(contributions(GoalType.minutes), {
      firstDay: ['time-only', 'cross-midnight'],
      secondDay: ['cross-midnight'],
    });
    expect(contributions(GoalType.days), {
      secondDay: ['cross-midnight'],
    });
  });

  test('time, days and finished books stop earning credit at their period target', () {
    final start = DateTime.utc(2026, 11, 23);
    final tomorrow = start.add(const Duration(days: 1));
    final end = start.add(const Duration(days: 7));

    final goal = ReadingGoal(
      id: 'weekly',
      type: GoalType.minutes,
      targetValue: 1,
      period: GoalPeriod.weekly,
      startDate: start,
      endDate: end,
      timezone: 'UTC',
      minimumMinutes: 1,
    );

    ReadingActivity entry(String id, DateTime from, int seconds, {String kind = 'reading'}) => ReadingActivity(
      id: id,
      bookId: id,
      bookTitle: id,
      startTime: from,
      endTime: from.add(Duration(seconds: seconds)),
      createdAt: from,
      kind: kind,
    );

    final first = entry('first', start, 40);
    final crossing = entry('crossing', start.add(const Duration(seconds: 30)), 60);
    final later = entry('later', tomorrow, 90);
    final ledger = [
      later,
      crossing,
      first,
      entry('book-a', start, 0, kind: 'completion'),
      entry('book-b', tomorrow, 0, kind: 'completion'),
    ];

    for (final type in GoalType.values.where((type) => type != GoalType.pages)) {
      final progress = projectGoal(
        goal.copyWith(type: type),
        ledger,
        tomorrow.add(const Duration(hours: 1)),
        collectContributions: true,
      );
      expect(progress.value, 1);
      expect(progress.contributionsByDay.keys, [start]);

      if (type == GoalType.books) {
        expect(progress.contributionsByDay[start]!.single.id, 'book-a');
      } else {
        expect(progress.secondsForDay([first, crossing], GoalRange(start, tomorrow)), 60);
        expect(progress.eligibleSecondsFor(crossing), 30);
        expect(progress.eligibleSecondsFor(later), 0);
        expect(progress.hasOverlappingTime, isTrue);
      }

      if (type == GoalType.days) {
        expect(progress.creditedDays, {start});
      }
    }

    expect(projectGoal(goal, ledger, end.add(const Duration(hours: 1))).value, 0);
  });

  test('each reading day stops crediting sessions when its minimum is reached', () {
    final monday = DateTime.utc(2026, 11, 23);
    final tuesday = monday.add(const Duration(days: 1));

    final goal = ReadingGoal(
      id: 'days',
      type: GoalType.days,
      targetValue: 2,
      minimumMinutes: 5,
      period: GoalPeriod.weekly,
      startDate: monday,
      endDate: monday.add(const Duration(days: 7)),
      timezone: 'UTC',
    );

    ReadingActivity session(String book, DateTime at, int minutes) => ReadingActivity(
      id: book,
      bookId: book,
      bookTitle: book,
      startTime: at,
      endTime: at.add(Duration(minutes: minutes)),
      createdAt: at,
    );

    final morning = session('Morning', monday, 7);
    final evening = session('Evening', monday.add(const Duration(hours: 18)), 60);
    final overnight = session('Overnight', tuesday.subtract(const Duration(minutes: 2)), 8);
    final ledger = [morning, evening, overnight];

    for (final now in [tuesday, tuesday.add(const Duration(hours: 1))]) {
      final progress = projectGoal(goal, ledger, now, collectContributions: true);
      expect(progress.contributionsByDay[monday], [morning]);
      expect(progress.eligibleSecondsFor(morning), 300);
      expect(progress.eligibleSecondsFor(evening), 0);

      if (now == tuesday) {
        expect(progress.value, 1);
        expect(progress.eligibleSecondsFor(overnight), 0);
      } else {
        expect(progress.value, 2);
        expect(progress.contributionsByDay[tuesday], [overnight]);
        expect(progress.eligibleSecondsFor(overnight), 300);
      }
    }
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
      startPosition: offset / 100,
      endPosition: (offset + 10) / 100,
      deviceType: 'linux',
      startTime: start.add(Duration(seconds: offset)),
      endTime: start.add(Duration(seconds: offset + 10)),
      createdAt: start.add(Duration(seconds: offset + 10)),
    );

    final grouped = groupReadingActivities([entry('a', 0), entry('b', 5), entry('c', 30)]).single;
    expect(grouped.seconds, 25);
    expect(grouped.constituentIds, ['a', 'b', 'c']);
    expect(grouped.session.startPosition, 0);
    expect(grouped.session.endPosition, 0.4);
    expect(grouped.session.deviceType, 'linux');
  });
}
