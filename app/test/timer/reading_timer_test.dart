import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/timer/reading_timer.dart';
import 'package:papyrus/timer/reading_timer_format.dart';

void main() {
  final start = DateTime.utc(2026, 11, 3, 12);
  final book = Book(id: 'digital', title: 'Digital book', author: 'Author', addedAt: start);

  test('clock supports sessions longer than an hour', () {
    expect(readingTimerClock(const Duration(hours: 2, minutes: 3, seconds: 4)), '2:03:04');
  });

  test('clock rollback does not produce negative reading intervals', () {
    final timer = ReadingTimer.start(book, start, 'device', []);
    expect(timer.elapsed(start.subtract(const Duration(minutes: 1))), Duration.zero);
    expect(timer.activities(start.subtract(const Duration(minutes: 1))), isEmpty);
  });

  for (final target in [null, 60]) {
    test('resume with a slower clock preserves ${target == null ? 'stopwatch' : 'countdown'} intervals', () {
      final timer = ReadingTimer.start(book, start, 'device', [], targetSeconds: target);
      final pausedAt = start.add(const Duration(seconds: 30));
      final paused = timer.stop(pausedAt);
      final resumed = paused.resume(pausedAt.subtract(const Duration(seconds: 1)));
      expect(resumed.runningSince, pausedAt);
      expect(resumed.elapsed(pausedAt), const Duration(seconds: 30));
      final finished = resumed.stop(pausedAt.add(const Duration(seconds: 10)), finish: true);
      expect(finished.intervals.last.start, finished.intervals.first.end);
      expect(finished.recorded, const Duration(seconds: 40));
    });
  }

  test('resume without recorded intervals cannot precede session creation', () {
    final paused = ReadingTimer.start(book, start, 'device', []).stop(start);
    final resumed = paused.resume(start.subtract(const Duration(seconds: 1)));
    expect(resumed.runningSince, start);
    expect(resumed.elapsed(start), Duration.zero);
  });

  test('continuing a completed countdown clamps a slower clock to the goal time', () {
    final timer = ReadingTimer.start(book, start, 'device', [], targetSeconds: 60);
    final goalTime = start.add(const Duration(minutes: 1));
    final finished = timer.stop(goalTime);
    final resumed = finished.resume(goalTime.subtract(const Duration(seconds: 1)), keepReading: true);
    expect(resumed.targetSeconds, isNull);
    expect(resumed.runningSince, goalTime);
    expect(resumed.elapsed(goalTime), const Duration(minutes: 1));
  });

  test('countdown stops at its goal and continuation excludes unattended time', () {
    final timer = ReadingTimer.start(book, start, 'device', [], targetSeconds: 60);
    final returnTime = start.add(const Duration(minutes: 5));
    expect(timer.elapsed(returnTime), const Duration(minutes: 1));
    expect(timer.reachedGoal(returnTime), isTrue);
    expect(timer.isRunning(returnTime), isFalse);
    final continued = timer.stop(returnTime).resume(returnTime, keepReading: true);
    final finishTime = returnTime.add(const Duration(minutes: 2));
    final finished = continued.stop(finishTime, finish: true);
    expect(finished.targetSeconds, isNull);
    expect(finished.elapsed(finishTime), const Duration(minutes: 3));
    expect(finished.phase, ReadingTimerPhase.finished);
  });
}
