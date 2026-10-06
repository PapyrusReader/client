import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/reading_activity_calendar.dart';
import 'package:papyrus/models/reading_activity.dart';

void main() {
  final start = DateTime.utc(2026, 10, 7);
  ReadingActivity entry(String id, int from, int to, {String kind = 'reading', String? correctionOf, int pages = 0}) =>
      ReadingActivity(
        id: id,
        bookId: 'book',
        bookTitle: 'Book',
        source: 'reader',
        startTime: start.add(Duration(minutes: from)),
        endTime: start.add(Duration(minutes: to)),
        createdAt: start.add(Duration(minutes: to)),
        kind: kind,
        correctionOf: correctionOf,
        pages: pages,
      );

  test('heatmap unions device overlap and retries, excludes corrections and panel gaps', () {
    final a = entry('a', 0, 10);
    final days = readingActivityCalendar(
      [a, a, entry('b', 5, 15), entry('c', 30, 35), entry('undo', 36, 36, kind: 'reversal', correctionOf: 'c')],
      range: GoalRange(start, start.add(const Duration(days: 1))),
      timezone: 'UTC',
      now: start.add(const Duration(hours: 1)),
    );
    expect(days[start]!.seconds, 15 * 60);
    expect(days[start]!.level, 2);
  });

  test('zero-duration pages and explicit completion count as activity without invented time', () {
    final days = readingActivityCalendar(
      [entry('pages', 0, 0, pages: 10), entry('finished', 1440, 1440, kind: 'completion')],
      range: GoalRange(start, start.add(const Duration(days: 3))),
      timezone: 'UTC',
      now: start.add(const Duration(days: 2)),
    );
    expect(days.length, 2);
    expect(days.values.every((day) => day.seconds == 0 && day.level == 1), isTrue);
  });

  test('splits at local midnight across DST and clips future exposure', () {
    const timezone = 'Europe/Vilnius';
    final beginning = DateTime.utc(2026, 3, 28, 21, 50); // 23:50 before the spring change
    final finish = DateTime.utc(2026, 3, 29, 22); // 01:00 after the change
    final days = readingActivityCalendar(
      [
        ReadingActivity(
          id: 'overnight',
          bookId: 'book',
          bookTitle: 'Book',
          startTime: beginning,
          endTime: finish,
          createdAt: finish,
        ),
      ],
      range: GoalRange(DateTime.utc(2026, 3, 28), DateTime.utc(2026, 3, 31)),
      timezone: timezone,
      now: DateTime.utc(2026, 3, 29, 21, 30),
    );
    expect(days[DateTime.utc(2026, 3, 28, 22)]!.seconds, 23 * 3600);
    expect(days[DateTime.utc(2026, 3, 27, 22)]!.seconds, 10 * 60);
    expect(days[DateTime.utc(2026, 3, 29, 21)]!.seconds, 30 * 60);
  });
}
