import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:papyrus/models/reading_goal.dart';

class GoalRange {
  const GoalRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

class GoalCalendar {
  static String systemTimezone = 'UTC';
  static bool _initialized = false;
  static void initialize() {
    if (_initialized) return;
    data.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location location(String name) {
    initialize();
    return name == 'UTC' ? tz.UTC : tz.getLocation(name);
  }

  static Future<String> deviceTimezone() async {
    initialize();
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    location(zone);
    systemTimezone = zone;
    return zone;
  }

  static DateTime local(DateTime date, String zone) => tz.TZDateTime.from(date, location(zone));
  static DateTime midnight(DateTime date, String zone) {
    final day = local(date, zone);
    return tz.TZDateTime(location(zone), day.year, day.month, day.day).toUtc();
  }

  static DateTime nextDay(DateTime date, String zone) {
    final day = local(date, zone);
    return tz.TZDateTime(location(zone), day.year, day.month, day.day + 1).toUtc();
  }

  static DateTime deadline(DateTime civilDate, String zone) =>
      tz.TZDateTime(location(zone), civilDate.year, civilDate.month, civilDate.day + 1).toUtc();

  static DateTime dayOffset(DateTime date, int offset, String zone) {
    final day = local(date, zone);
    return tz.TZDateTime(location(zone), day.year, day.month, day.day + offset).toUtc();
  }

  static GoalRange calendarPeriod(GoalPeriod period, DateTime date, String zone) {
    final day = local(date, zone);
    final loc = location(zone);
    final start = switch (period) {
      GoalPeriod.daily => tz.TZDateTime(loc, day.year, day.month, day.day),
      GoalPeriod.weekly => tz.TZDateTime(loc, day.year, day.month, day.day - day.weekday + 1),
      GoalPeriod.monthly => tz.TZDateTime(loc, day.year, day.month),
      GoalPeriod.yearly => tz.TZDateTime(loc, day.year),
      GoalPeriod.custom => throw ArgumentError('A deadline needs explicit dates'),
    };
    final end = switch (period) {
      GoalPeriod.daily => tz.TZDateTime(loc, start.year, start.month, start.day + 1),
      GoalPeriod.weekly => tz.TZDateTime(loc, start.year, start.month, start.day + 7),
      GoalPeriod.monthly => tz.TZDateTime(loc, start.year, start.month + 1),
      GoalPeriod.yearly => tz.TZDateTime(loc, start.year + 1),
      GoalPeriod.custom => throw ArgumentError('A deadline needs explicit dates'),
    };
    return GoalRange(start.toUtc(), end.toUtc());
  }

  static DateTime effectiveNow(ReadingGoal goal, DateTime now) =>
      goal.isArchived && goal.rules.isNotEmpty && goal.rules.last.at.isBefore(now) ? goal.rules.last.at : now;
  static GoalRange currentPeriod(ReadingGoal goal, DateTime now) =>
      goal.isRecurring && goal.period != GoalPeriod.custom && !now.isBefore(goal.startDate)
      ? calendarPeriod(goal.period, effectiveNow(goal, now), goal.timezone)
      : GoalRange(goal.startDate, goal.endDate);
  static List<GoalRange> pastPeriods(ReadingGoal goal, DateTime now) {
    now = effectiveNow(goal, now);
    final result = <GoalRange>[];
    var period = GoalRange(goal.startDate, goal.endDate);
    while (!period.end.isAfter(now)) {
      result.add(period);
      if (!goal.isRecurring || goal.period == GoalPeriod.custom) break;
      period = calendarPeriod(goal.period, period.end, goal.timezone);
    }
    return result;
  }
}
