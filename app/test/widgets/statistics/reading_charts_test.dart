import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/statistics_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/statistics/reading_charts.dart';

void main() {
  final activities = List.generate(11, (index) {
    final date = DateTime(2026, 10, 23 + index);
    return StatisticsActivity(
      date: date,
      endDate: DateTime(date.year, date.month, date.day + 1),
      seconds: index == 0 ? 49 : (index == 1 ? 7 : 0),
      pages: 0,
      bucketSize: StatisticsBucketSize.day,
      booksRead: const [],
    );
  });

  Future<void> pumpChart(
    WidgetTester tester,
    double width, {
    List<StatisticsActivity>? data,
    ReadingActivityMetric metric = ReadingActivityMetric.time,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReadingActivityBarChart(activities: data ?? activities, metric: metric, isDesktop: width > 600),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('sub-minute sessions have a readable seconds scale and intermediate grid lines', (tester) async {
    await pumpChart(tester, 800);
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(find.text('15s'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('45s'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(data.gridData.show, isTrue);
    expect(data.maxY / data.gridData.horizontalInterval!, greaterThanOrEqualTo(3));
    expect(data.borderData.show, isTrue);
    expect(data.barGroups.first.barRods.first.toY, closeTo(49 / 60, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide daily charts label every day including both range boundaries', (tester) async {
    await pumpChart(tester, 1200);
    expect(find.text('Oct 23'), findsOneWidget);
    expect(find.text('Nov 2'), findsOneWidget);

    for (final day in ['24', '25', '26', '27', '28', '29', '30', '31', 'Nov 1']) {
      expect(find.text(day), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow charts retain the latest date and a tick for every bucket', (tester) async {
    await pumpChart(tester, 300);
    expect(find.text('Nov 2'), findsOneWidget);
    expect(find.text('24'), findsNothing);

    for (var index = 0; index < activities.length; index++) {
      expect(find.byKey(ValueKey('activity-axis-tick-$index')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('monthly axis labels stay separated on desktop and phone', (tester) async {
    final months = List.generate(23, (index) {
      final date = DateTime(2025, 1 + index);
      return StatisticsActivity(
        date: date,
        endDate: DateTime(date.year, date.month + 1),
        seconds: index == 0 ? 3600 : 0,
        pages: 0,
        bucketSize: StatisticsBucketSize.month,
        booksRead: const [],
      );
    });

    for (final width in [650.0, 360.0]) {
      await pumpChart(tester, width, data: months);
      expect(find.text('Nov 26'), findsOneWidget);
      final labels = find.byWidgetPredicate(
        (widget) => widget is Text && RegExp(r'^[A-Z][a-z]{2} \d{2}$').hasMatch(widget.data ?? ''),
      );
      final rectangles = labels.evaluate().map((element) => tester.getRect(find.byWidget(element.widget))).toList()
        ..sort((left, right) => left.left.compareTo(right.left));

      final interval = rectangles[1].center.dx - rectangles[0].center.dx;

      for (var index = 1; index < rectangles.length; index++) {
        expect(rectangles[index].left - rectangles[index - 1].right, greaterThanOrEqualTo(8));
        expect(rectangles[index].center.dx - rectangles[index - 1].center.dx, closeTo(interval, 0.1));
      }

      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Time and Pages use identical centered bars and complete grid boundaries', (tester) async {
    final activity = StatisticsActivity(
      date: DateTime(2026, 11, 2),
      endDate: DateTime(2026, 11, 3),
      seconds: 70,
      pages: 2,
      bucketSize: StatisticsBucketSize.day,
      booksRead: const [],
    );
    final bars = <BarChartRodData>[];

    for (final metric in ReadingActivityMetric.values) {
      await pumpChart(tester, 800, data: [activity], metric: metric);
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      bars.add(data.barGroups.single.barRods.single);
      expect(find.byType(LineChart), findsNothing);
      expect(data.borderData.border.top.style, BorderStyle.solid);
      expect(data.borderData.border.top.width, greaterThan(0));
      expect(data.borderData.border.bottom.width, greaterThan(0));
      expect(tester.getCenter(find.text('Mon')).dx, closeTo(420, 1));
      expect(find.text(metric == ReadingActivityMetric.time ? '1.5m' : '3'), findsOneWidget);
    }

    expect(bars[0].width, bars[1].width);
    expect(bars[0].color, bars[1].color);
    expect(bars[0].borderRadius, bars[1].borderRadius);
    expect(bars[0].toY, closeTo(70 / 60, .0001));
    expect(bars[1].toY, 2);
  });

  testWidgets('24-day ranges have uniform label intervals with no missing bucket ticks', (tester) async {
    final days = List.generate(24, (index) {
      final date = DateTime(2026, 10, 10 + index);
      return StatisticsActivity(
        date: date,
        endDate: DateTime(date.year, date.month, date.day + 1),
        seconds: index == 23 ? 70 : 0,
        pages: 0,
        bucketSize: StatisticsBucketSize.day,
        booksRead: const [],
      );
    });

    for (final width in [700.0, 350.0]) {
      await pumpChart(tester, width, data: days);
      final labels = find.byWidgetPredicate(
        (widget) => widget is Text && RegExp(r'^(Oct \d+|Nov \d+|\d{2})$').hasMatch(widget.data ?? ''),
      );
      final positions = labels.evaluate().map((element) => tester.getCenter(find.byWidget(element.widget)).dx).toList()
        ..sort();
      final interval = positions[1] - positions[0];

      for (var index = 1; index < positions.length; index++) {
        expect(positions[index] - positions[index - 1], closeTo(interval, 0.1));
      }

      for (var index = 0; index < days.length; index++) {
        expect(find.byKey(ValueKey('activity-axis-tick-$index')), findsOneWidget);
      }

      expect(find.text('Nov 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
