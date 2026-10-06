import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/pages/goals_page.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'support/tracking_app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real EPUB/PDF reader activity reaches Goals and survives closing', (tester) async {
    final app = TrackingValidationApp();
    await app.initialize();
    await tester.pumpWidget(app.build());
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);
    for (final format in ['epub', 'pdf']) {
      await tester.tap(find.text('Open $format'));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byType(PapyrusReader).evaluate().isNotEmpty && find.byTooltip('Back').evaluate().isNotEmpty) break;
      }
      expect(find.byType(PapyrusReader), findsOneWidget);
      // Pump real frames while asynchronous parsing/layout reaches ready content.
      // EPUB cover-only chapters have no text coverage, so turn to readable content.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (format == 'epub' && i >= 3 && i <= 5 && find.byTooltip('Next').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Next'));
        }
        if (app.store.readingActivities.any((a) => a.bookId == format && a.coverage.isNotEmpty)) break;
      }
      if (find.text('Not yet').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not yet'));
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoalsPage), findsOneWidget);
      final activity = app.store.effectiveReadingActivities
          .where((a) => a.bookId == format && a.kind == 'reading')
          .toList();
      expect(activity, isNotEmpty);
      expect(activity.fold<int>(0, (n, a) => n + a.seconds), greaterThanOrEqualTo(10));
      expect(activity.expand((a) => a.coverage), isNotEmpty);
    }
    final totals = app.goals.current;
    expect(totals.firstWhere((p) => p.goal.type == GoalType.minutes).seconds, greaterThanOrEqualTo(20));
    binding.reportData = {
      'activity_count': app.store.readingActivities.length,
      'seconds': totals.first.seconds,
      'estimated_pages': totals.first.pages,
      'sources': app.store.readingActivities.map((a) => a.source).toSet().toList(),
    };
    await tester.pumpWidget(const SizedBox.shrink());
    await app.close();
  });
}
