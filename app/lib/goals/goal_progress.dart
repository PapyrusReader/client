import 'dart:math';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';

class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.range,
    required this.seconds,
    required this.pages,
    required this.finishedBooks,
    required this.days,
    required this.activities,
    required this.estimated,
    required this.qualifiedDays,
    this.contributionsByDay = const {},
    this.activityIntervals = const {},
    this.pageCredits = const {},
    this.hasOverlappingTime = false,
    this.hasCreationCutoff = false,
  });

  final ReadingGoal goal;
  final GoalRange range;
  final int seconds;
  final double pages;
  final int finishedBooks;
  final int days;
  final List<ReadingActivity> activities;
  final bool estimated;
  final Set<DateTime> qualifiedDays;

  final Map<DateTime, List<ReadingActivity>> contributionsByDay;

  /// Eligible intervals for presentation only; the ledger remains unchanged.
  final Map<String, List<(double, double)>> activityIntervals;

  final Map<String, double> pageCredits;
  final bool hasOverlappingTime;
  final bool hasCreationCutoff;

  Iterable<(double, double)> _intervalsFor(ReadingActivity activity) => [
    for (final id in activity.constituentIds.isEmpty ? [activity.id] : activity.constituentIds)
      ...?activityIntervals[id],
  ];

  int eligibleSecondsFor(ReadingActivity activity) => unionLength(_intervalsFor(activity).toList()).floor();

  int get value => min(goal.targetValue, switch (goal.type) {
    GoalType.books => finishedBooks,
    GoalType.pages => pages.floor(),
    GoalType.minutes => seconds ~/ 60,
    GoalType.days => days,
  });

  Set<DateTime> get creditedDays => goal.type == GoalType.days && days > goal.targetValue
      ? (qualifiedDays.toList()..sort()).take(goal.targetValue).toSet()
      : qualifiedDays;

  double pagesFor(ReadingActivity activity) => activity.constituentIds.isEmpty
      ? pageCredits[activity.id] ?? 0
      : activity.constituentIds.fold(0.0, (total, id) => total + (pageCredits[id] ?? 0));

  int secondsForDay(Iterable<ReadingActivity> entries, GoalRange day) {
    final start = day.start.microsecondsSinceEpoch / 1000000;
    final end = day.end.microsecondsSinceEpoch / 1000000;

    return unionLength([
      for (final entry in entries)
        for (final interval in _intervalsFor(entry))
          if (interval.$1 < end && interval.$2 > start) (max(start, interval.$1), min(end, interval.$2)),
    ]).floor();
  }

  double get fraction {
    final currentValue = switch (goal.type) {
      GoalType.minutes => seconds / 60,
      GoalType.pages => pages,
      _ => value,
    };

    return (currentValue / goal.targetValue).clamp(0, 1);
  }

  bool get reached => fraction >= 1;
  ReadingGoal get projected => goal.copyWith(currentValue: value, estimatedPages: estimated);
}

GoalRule ruleAt(ReadingGoal goal, DateTime at) {
  var rule = GoalRule(
    at: goal.createdAt,
    target: goal.targetValue,
    title: goal.title,
    active: goal.isActive,
    archived: goal.isArchived,
  );

  final rules = [...goal.rules]..sort((left, right) => left.at.compareTo(right.at));

  for (final next in rules) {
    if (next.at.isAfter(at)) {
      break;
    }

    rule = next;
  }

  return rule;
}

bool matchesGoal(ReadingGoal goal, ReadingActivity activity) => switch (goal.scope) {
  GoalScope.library => true,
  GoalScope.book => goal.selectedBookIds.contains(activity.bookId),
  GoalScope.shelf => activity.shelfIds.contains(goal.scopeId),
};

/// UTC interval unions remove concurrent-device double counting.
double unionLength(List<(double, double)> ranges) {
  if (ranges.isEmpty) {
    return 0;
  }

  ranges.sort((left, right) => left.$1.compareTo(right.$1));
  var start = ranges.first.$1;
  var end = ranges.first.$2;
  var total = 0.0;

  for (final range in ranges.skip(1)) {
    if (range.$1 <= end) {
      end = max(end, range.$2);
    } else {
      total += end - start;
      start = range.$1;
      end = range.$2;
    }
  }

  return total + end - start;
}

/// Merge a page extent into the sorted, disjoint ranges for one book, day and page key.
double _addCoverage(List<(double, double)> ranges, double start, double end) {
  if (end <= start) {
    return 0;
  }

  var index = ranges.length;

  while (index > 0 && ranges[index - 1].$2 >= start) {
    index--;
  }

  if (index < ranges.length && ranges[index].$1 <= start && ranges[index].$2 >= end) {
    return 0;
  }

  var next = index;
  var previousLength = 0.0;

  while (next < ranges.length && ranges[next].$1 <= end) {
    previousLength += ranges[next].$2 - ranges[next].$1;
    start = min(start, ranges[next].$1);
    end = max(end, ranges[next].$2);
    next++;
  }

  ranges.replaceRange(index, next, [(start, end)]);
  return end - start - previousLength;
}

/// First instant at which the union of the intervals reaches the requested duration.
double? _timeTargetEnd(List<(double, double)> intervals, double remaining) {
  intervals.sort((left, right) => left.$1.compareTo(right.$1));
  var previousEnd = double.negativeInfinity;

  for (final (start, end) in intervals) {
    final from = max(start, previousEnd);

    if (from >= end) {
      continue;
    }

    if (end - from >= remaining) {
      return from + remaining;
    }

    remaining -= end - from;
    previousEnd = end;
  }

  return null;
}

GoalProgress projectGoal(
  ReadingGoal definition,
  Iterable<ReadingActivity> ledger,
  DateTime now, {
  GoalRange? period,
  bool collectContributions = false,
}) {
  final range = period ?? GoalCalendar.currentPeriod(definition, now);
  final historical = !range.end.isAfter(now);
  final rule = ruleAt(definition, historical ? range.end.subtract(const Duration(microseconds: 1)) : now);

  final goal = definition.copyWith(
    targetValue: rule.target,
    title: rule.title,
    startDate: range.start,
    endDate: range.end,
    isActive: historical ? rule.active : definition.isActive,
    isArchived: historical
        ? (!definition.isRecurring && definition.isArchived || rule.archived)
        : definition.isArchived,
  );

  final cutoff = definition.createdAt.isAfter(range.start) ? definition.createdAt : range.start;
  final limit = range.end.isBefore(now) ? range.end : now;
  final times = <DateTime, List<(double, double)>>{};
  final pages = <String, List<(double, double)>>{};
  final scales = <String, double>{};
  final books = <String>{};
  final contributions = <DateTime, List<ReadingActivity>>{};
  final counted = <ReadingActivity>[];
  final activityIntervals = <String, List<(double, double)>>{};
  var hasCreationCutoff = false;
  final pageCredits = <String, double>{};
  var remainingPages = goal.targetValue.toDouble();
  var manualPages = 0;
  var estimated = false;

  final boundaries =
      definition.rules.map((rule) => rule.at).where((at) => at.isAfter(cutoff) && at.isBefore(limit)).toList()..sort();

  final effective = effectiveActivities(ledger)
    ..sort((left, right) {
      final order = left.endTime.compareTo(right.endTime);
      return order == 0 ? left.id.compareTo(right.id) : order;
    });

  for (final activity in effective) {
    if (!matchesGoal(definition, activity)) {
      continue;
    }

    var contributed = false;

    final point = activity.kind == 'reading' && activity.endTime.isAfter(activity.startTime)
        ? activity.endTime.subtract(const Duration(microseconds: 1))
        : activity.endTime;

    final pointRule = ruleAt(definition, point);

    if (!point.isBefore(cutoff) &&
        point.isBefore(range.end) &&
        !point.isAfter(now) &&
        pointRule.active &&
        !pointRule.archived) {
      if (activity.kind == 'completion') {
        final firstCompletion = books.add(activity.bookId);

        if (collectContributions &&
            goal.type == GoalType.books &&
            firstCompletion &&
            books.length <= goal.targetValue) {
          final day = GoalCalendar.midnight(point, goal.timezone);
          contributions.putIfAbsent(day, () => []).add(activity);
        }

        contributed = true;
      }

      if (activity.kind == 'reading') {
        manualPages += activity.pages;
        contributed |= activity.pages > 0 || activity.coverage.isNotEmpty;
        final day = GoalCalendar.midnight(point, goal.timezone);
        var addedPages = activity.pages.toDouble();

        for (final coverage in activity.coverage) {
          final key = '${day.toIso8601String()}:${activity.bookId}:${coverage.key}';
          final scale = scales.putIfAbsent(key, () => coverage.pagesPerUnit);
          final ranges = pages.putIfAbsent(key, () => []);

          if (goal.type == GoalType.pages) {
            final extended = _addCoverage(ranges, coverage.start, coverage.end);
            estimated |= coverage.estimated && extended > 0 && remainingPages > addedPages;
            addedPages += extended * scale;
          } else {
            ranges.add((coverage.start, coverage.end));
            estimated |= coverage.estimated;
          }
        }

        if (goal.type == GoalType.pages && addedPages > 0 && remainingPages > 0) {
          final credit = min(addedPages, remainingPages);
          remainingPages -= credit;

          if (collectContributions) {
            pageCredits[activity.id] = credit;
            contributions.putIfAbsent(day, () => []).add(activity);
          }
        }
      }
    }

    if (activity.kind == 'reading') {
      var cursor = activity.startTime.isAfter(cutoff) ? activity.startTime : cutoff;
      final end = activity.endTime.isBefore(limit) ? activity.endTime : limit;

      while (cursor.isBefore(end)) {
        final day = GoalCalendar.midnight(cursor, goal.timezone);
        var stop = GoalCalendar.nextDay(cursor, goal.timezone);

        if (stop.isAfter(end)) {
          stop = end;
        }

        for (final boundary in boundaries) {
          if (boundary.isAfter(cursor) && boundary.isBefore(stop)) {
            stop = boundary;
          }
        }

        final active = ruleAt(definition, cursor);

        if (active.active && !active.archived) {
          final interval = (cursor.microsecondsSinceEpoch / 1000000, stop.microsecondsSinceEpoch / 1000000);
          times.putIfAbsent(day, () => []).add(interval);
          activityIntervals.putIfAbsent(activity.id, () => []).add(interval);
          if (collectContributions && (goal.type == GoalType.minutes || goal.type == GoalType.days)) {
            final entries = contributions.putIfAbsent(day, () => []);

            if (entries.isEmpty || entries.last != activity) {
              entries.add(activity);
            }
          }

          hasCreationCutoff |= activity.startTime.isBefore(definition.createdAt);
          contributed = true;
        }

        cursor = stop;
      }
    }

    if (contributed) {
      counted.add(activity);
    }
  }

  final dailySeconds = times.map((day, intervals) => MapEntry(day, unionLength(intervals)));

  final qualified = dailySeconds.entries
      .where((entry) => entry.value >= definition.minimumMinutes * 60)
      .map((entry) => entry.key)
      .toSet();

  final totalSeconds = dailySeconds.values.fold(0.0, (total, value) => total + value);
  final dailyCutoffs = <DateTime, double>{};
  final dayGoal = collectContributions && goal.type == GoalType.days;
  final completedTimeGoal =
      collectContributions && goal.type == GoalType.minutes && totalSeconds >= goal.targetValue * 60;

  if (dayGoal) {
    final days = qualified.toList()..sort();

    for (final day in days.take(goal.targetValue)) {
      dailyCutoffs[day] = _timeTargetEnd(times[day]!, goal.minimumMinutes * 60.0)!;
    }
  } else if (completedTimeGoal) {
    final completion = _timeTargetEnd(times.values.expand((intervals) => intervals).toList(), goal.targetValue * 60.0)!;

    for (final day in times.keys) {
      dailyCutoffs[day] = completion;
    }
  }

  var creditedSeconds = totalSeconds;

  if (dayGoal || completedTimeGoal) {
    final creditedIds = <DateTime, Set<String>>{};

    activityIntervals.updateAll((id, intervals) {
      final credited = <(double, double)>[];

      for (final (start, end) in intervals) {
        final instant = DateTime.fromMicrosecondsSinceEpoch((start * 1000000).round(), isUtc: true);
        final day = GoalCalendar.midnight(instant, goal.timezone);
        final cutoff = dailyCutoffs[day];

        if (cutoff != null && start < cutoff) {
          credited.add((start, min(end, cutoff)));
          creditedIds.putIfAbsent(day, () => {}).add(id);
        }
      }

      return credited;
    });

    for (final day in contributions.entries) {
      final ids = creditedIds[day.key];
      day.value.removeWhere((entry) => ids == null || !ids.contains(entry.id));
    }

    contributions.removeWhere((day, entries) => entries.isEmpty);
    creditedSeconds = unionLength(activityIntervals.values.expand((intervals) => intervals).toList());
  }

  final pageCount =
      manualPages +
      pages.entries.fold<double>(0, (total, entry) => total + unionLength(entry.value) * scales[entry.key]!);

  counted.sort((left, right) => right.startTime.compareTo(left.startTime));

  return GoalProgress(
    goal: goal,
    range: range,
    seconds: totalSeconds.floor(),
    pages: pageCount,
    finishedBooks: books.length,
    days: qualified.length,
    activities: counted,
    estimated: estimated,
    qualifiedDays: qualified,
    contributionsByDay: contributions,
    pageCredits: pageCredits,
    activityIntervals: activityIntervals,
    hasCreationCutoff: hasCreationCutoff,
    hasOverlappingTime:
        activityIntervals.values.fold<double>(0, (total, ranges) => total + unionLength([...ranges])) >
        creditedSeconds + .000001,
  );
}
