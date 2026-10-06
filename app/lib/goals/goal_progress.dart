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
  int get value => switch (goal.type) {
    GoalType.books => finishedBooks,
    GoalType.pages => pages.floor(),
    GoalType.minutes => seconds ~/ 60,
    GoalType.days => days,
  };
  double get fraction =>
      ((goal.type == GoalType.minutes
                  ? seconds / 60
                  : goal.type == GoalType.pages
                  ? pages
                  : value) /
              goal.targetValue)
          .clamp(0, 1);
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
  final rules = [...goal.rules]..sort((a, b) => a.at.compareTo(b.at));
  for (final next in rules) {
    if (next.at.isAfter(at)) break;
    rule = next;
  }
  return rule;
}

bool matchesGoal(ReadingGoal goal, ReadingActivity activity) => switch (goal.scope) {
  GoalScope.library => true,
  GoalScope.book => activity.bookId == goal.scopeId,
  GoalScope.shelf => activity.shelfIds.contains(goal.scopeId),
};

/// UTC interval unions remove concurrent-device double counting.
double unionLength(List<(double, double)> ranges) {
  if (ranges.isEmpty) return 0;
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
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

GoalProgress projectGoal(ReadingGoal definition, Iterable<ReadingActivity> ledger, DateTime now, {GoalRange? period}) {
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
  final counted = <ReadingActivity>[];
  var manualPages = 0;
  var estimated = false;
  final boundaries =
      definition.rules.map((rule) => rule.at).where((at) => at.isAfter(cutoff) && at.isBefore(limit)).toList()..sort();
  final effective = effectiveActivities(ledger)
    ..sort((a, b) {
      final order = a.endTime.compareTo(b.endTime);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
  for (final activity in effective) {
    if (!matchesGoal(definition, activity)) continue;
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
        books.add(activity.bookId);
        contributed = true;
      }
      if (activity.kind == 'reading') {
        manualPages += activity.pages;
        contributed |= activity.pages > 0 || activity.coverage.isNotEmpty;
        final day = GoalCalendar.midnight(point, goal.timezone).toIso8601String();
        for (final coverage in activity.coverage) {
          final key = '$day:${activity.bookId}:${coverage.key}';
          pages.putIfAbsent(key, () => []).add((coverage.start, coverage.end));
          scales.putIfAbsent(key, () => coverage.pagesPerUnit);
          estimated |= coverage.estimated;
        }
      }
    }
    if (activity.kind == 'reading') {
      var cursor = activity.startTime.isAfter(cutoff) ? activity.startTime : cutoff;
      final end = activity.endTime.isBefore(limit) ? activity.endTime : limit;
      while (cursor.isBefore(end)) {
        final day = GoalCalendar.midnight(cursor, goal.timezone);
        var stop = GoalCalendar.nextDay(cursor, goal.timezone);
        if (stop.isAfter(end)) stop = end;
        for (final boundary in boundaries) {
          if (boundary.isAfter(cursor) && boundary.isBefore(stop)) stop = boundary;
        }
        final active = ruleAt(definition, cursor);
        if (active.active && !active.archived) {
          times.putIfAbsent(day, () => []).add((
            cursor.microsecondsSinceEpoch / 1000000,
            stop.microsecondsSinceEpoch / 1000000,
          ));
          contributed = true;
        }
        cursor = stop;
      }
    }
    if (contributed) counted.add(activity);
  }
  final dailySeconds = times.map((day, intervals) => MapEntry(day, unionLength(intervals)));
  final qualified = dailySeconds.entries
      .where((entry) => entry.value >= definition.minimumMinutes * 60)
      .map((entry) => entry.key)
      .toSet();
  final pageCount =
      manualPages +
      pages.entries.fold<double>(0, (total, entry) => total + unionLength(entry.value) * scales[entry.key]!);
  counted.sort((a, b) => b.startTime.compareTo(a.startTime));
  return GoalProgress(
    goal: goal,
    range: range,
    seconds: dailySeconds.values.fold<double>(0, (a, b) => a + b).floor(),
    pages: pageCount,
    finishedBooks: books.length,
    days: qualified.length,
    activities: counted,
    estimated: estimated,
    qualifiedDays: qualified,
  );
}
