import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/timer/reading_timer_clock.dart';

void main() {
  for (final width in [200.0, 300.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('clock labels stay anchored at width $width and text scale $scale', (tester) async {
        Future<void> show(Duration time) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: ReadingTimerClock(time: time, progress: 0.5, countdown: true, status: 'Ready'),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await show(const Duration(minutes: 59, seconds: 59));
        final label = tester.getRect(find.text('Time remaining'));
        final badge = tester.getRect(find.text('Ready'));
        final clock = tester.getRect(find.byType(ReadingTimerClock));

        for (final time in [
          const Duration(hours: 1),
          const Duration(hours: 9, minutes: 59, seconds: 59),
          const Duration(hours: 10),
          const Duration(hours: 16, minutes: 40),
          const Duration(hours: 100),
          Duration.zero,
        ]) {
          await show(time);
          expect(tester.getRect(find.text('Time remaining')), label);
          expect(tester.getRect(find.text('Ready')), badge);
          expect(tester.getRect(find.byType(ReadingTimerClock)), clock);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
