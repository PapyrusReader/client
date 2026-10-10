import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_activity.dart';

class ReadingActivityDay {
  const ReadingActivityDay({required this.seconds, required this.hasActivity});
  final int seconds;
  final bool hasActivity;

  int get level => switch (!hasActivity) {
    true => 0,
    false when seconds < 15 * 60 => 1,
    false when seconds < 30 * 60 => 2,
    false when seconds < 60 * 60 => 3,
    false => 4,
  };
}

/// Calendar presentation uses the same interval union and corrections as goals.
/// Consume raw checkpoints, not grouped sessions whose elapsed span includes pauses.
Map<DateTime, ReadingActivityDay> readingActivityCalendar(
  Iterable<ReadingActivity> ledger, {
  required GoalRange range,
  required String timezone,
  required DateTime now,
}) {
  final intervals = <DateTime, List<(double, double)>>{};
  final active = <DateTime>{};
  final limit = now.isBefore(range.end) ? now : range.end;

  for (final entry in effectiveActivities(ledger)) {
    final point = entry.kind == 'reading' && entry.endTime.isAfter(entry.startTime)
        ? entry.endTime.subtract(const Duration(microseconds: 1))
        : entry.endTime;

    if (range.contains(point) &&
        !point.isAfter(now) &&
        (entry.kind == 'completion' || entry.pages > 0 || entry.coverage.isNotEmpty)) {
      active.add(GoalCalendar.midnight(point, timezone));
    }

    if (entry.kind != 'reading') {
      continue;
    }

    var cursor = entry.startTime.isAfter(range.start) ? entry.startTime : range.start;
    final end = entry.endTime.isBefore(limit) ? entry.endTime : limit;

    while (cursor.isBefore(end)) {
      final day = GoalCalendar.midnight(cursor, timezone);
      final boundary = GoalCalendar.nextDay(cursor, timezone);
      final stop = boundary.isBefore(end) ? boundary : end;

      intervals.putIfAbsent(day, () => []).add((
        cursor.microsecondsSinceEpoch / 1e6,
        stop.microsecondsSinceEpoch / 1e6,
      ));

      active.add(day);
      cursor = stop;
    }
  }

  return {
    for (final day in active)
      day: ReadingActivityDay(seconds: unionLength(intervals[day] ?? []).floor(), hasActivity: true),
  };
}
