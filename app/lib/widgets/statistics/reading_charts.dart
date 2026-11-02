import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/models/daily_activity.dart';
import 'package:papyrus/providers/statistics_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';

double _readingMinutes(DailyActivity activity) =>
    activity is StatisticsActivity ? activity.minutes : activity.readingMinutes.toDouble();

double _pagesRead(DailyActivity activity) =>
    activity is StatisticsActivity ? activity.pages : activity.pagesRead.toDouble();

String _activityLabel(DailyActivity activity) =>
    activity is StatisticsActivity ? activity.intervalLabel : activity.dayName;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Formats a minutes value for the Y-axis (e.g., "0", "30m", "1h", "1.5h").
String _formatMinutesLabel(double value) {
  if (value <= 0) {
    return '0';
  }

  if (value < 1) {
    return '${(value * 60).round()}s';
  }

  if (value < 60) {
    return value == value.roundToDouble() ? '${value.round()}m' : '${value.toStringAsFixed(1)}m';
  }

  final hours = value / 60;

  if (hours == hours.truncateToDouble()) {
    return '${hours.toInt()}h';
  }

  return '${hours.toStringAsFixed(1)}h';
}

/// Formats a pages value for the Y-axis.
String _formatPagesLabel(double value) {
  if (value <= 0) {
    return '0';
  }

  return '${value.round()}';
}

/// Computes a nice Y-axis interval and maxY that align cleanly.
({double interval, double maxY}) _niceYAxis(double maxValue, {bool minutes = false}) {
  if (maxValue <= 0) {
    return (interval: 1.0, maxY: 4.0);
  }

  final rawInterval = maxValue / 4;
  final niceSteps = [
    if (minutes) ...[1 / 60, 5 / 60, 10 / 60, 15 / 60, 30 / 60],
    1,
    2,
    5,
    10,
    15,
    20,
    25,
    30,
    50,
    60,
    100,
    120,
    150,
    200,
    250,
    300,
    500,
    1000,
  ];
  var interval = (rawInterval / 100).ceil() * 100.0;

  for (final step in niceSteps) {
    if (step >= rawInterval) {
      interval = step.toDouble();
      break;
    }
  }

  final maxY = math.max(3, (maxValue / interval).ceil()) * interval;
  return (interval: interval, maxY: maxY);
}

/// Builds a Y-axis title widget.
Widget _buildYAxisLabel(double value, TextTheme textTheme, ColorScheme colorScheme, String Function(double) formatter) {
  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Text(
      formatter(value),
      style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
    ),
  );
}

String _activityAxisLabel(DailyActivity activity, int index, int count) {
  if (activity is StatisticsActivity && activity.bucketSize != StatisticsBucketSize.day) {
    return activity.axisLabel;
  }

  if (count <= 7) {
    return activity.dayLabel;
  }

  if (index == 0 || index == count - 1 || activity.date.day == 1) {
    return '${_months[activity.date.month - 1]} ${activity.date.day}';
  }

  return '${activity.date.day}';
}

int _bottomLabelStep(BuildContext context, double width, List<DailyActivity> activities) {
  final textScaler = MediaQuery.textScalerOf(context);
  final availableWidth = math.max(1.0, width - textScaler.scale(60));
  final style = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold);
  var labelWidth = 0.0;

  for (var index = 0; index < activities.length; index++) {
    final painter = TextPainter(
      text: TextSpan(text: _activityAxisLabel(activities[index], index, activities.length), style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();

    labelWidth = math.max(labelWidth, painter.width);
    painter.dispose();
  }

  final bucketWidth = availableWidth / math.max(1, activities.length);
  final step = math.max(1, ((labelWidth + 12) / bucketWidth).ceil());
  return step;
}

/// Builds a bottom axis label for chart data points.
Widget _buildBottomLabel(
  double value,
  List<DailyActivity> activities,
  TextTheme textTheme,
  ColorScheme colorScheme, {
  int labelStep = 1,
}) {
  final index = value.toInt();

  if (index < 0 || index >= activities.length || value != index.toDouble()) {
    return const SizedBox.shrink();
  }

  final count = activities.length;
  final showLabel = (count - 1 - index) % labelStep == 0;
  final activity = activities[index];
  final label = _activityAxisLabel(activity, index, count);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        key: ValueKey('activity-axis-tick-$index'),
        width: 1,
        height: 4,
        color: colorScheme.outline,
      ),
      if (showLabel) ...[
        const SizedBox(height: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: activity.isToday ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: activity.isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ],
  );
}

enum ReadingActivityMetric { time, pages }

/// Shared plotting and axes keep Time and Pages visually consistent.
class ReadingActivityBarChart extends StatelessWidget {
  final List<DailyActivity> activities;
  final ReadingActivityMetric metric;
  final bool isDesktop;

  const ReadingActivityBarChart({
    super.key,
    required this.activities,
    this.metric = ReadingActivityMetric.time,
    this.isDesktop = false,
  });

  double _value(DailyActivity activity) =>
      metric == ReadingActivityMetric.time ? _readingMinutes(activity) : _pagesRead(activity);

  String _valueLabel(DailyActivity activity) {
    if (metric == ReadingActivityMetric.time) {
      return activity.readingTimeLabel;
    }

    final pages = _pagesRead(activity);
    final count = pages == pages.roundToDouble() ? '${pages.round()}' : pages.toStringAsFixed(1);
    return '$count ${pages == 1 ? 'page' : 'pages'}';
  }

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return _buildEmptyState(context);
    }

    return _buildDailyChart(context, Theme.of(context).colorScheme, Theme.of(context).textTheme, isDesktop ? 200 : 160);
  }

  Widget _buildDailyChart(BuildContext context, ColorScheme colorScheme, TextTheme textTheme, double chartHeight) {
    final maxValue = activities.map(_value).reduce(math.max);
    final yAxis = _niceYAxis(maxValue, minutes: metric == ReadingActivityMetric.time);

    return SizedBox(
      height: chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - MediaQuery.textScalerOf(context).scale(60);
          final barWidth = (availableWidth / activities.length * 0.6).clamp(4.0, isDesktop ? 20.0 : 16.0);
          final labelStep = _bottomLabelStep(context, constraints.maxWidth, activities);

          return BarChart(
            key: ValueKey((AppMotion.disabled(context), metric)),
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: yAxis.maxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => colorScheme.inverseSurface,
                  tooltipRoundedRadius: AppRadius.md,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final activity = activities[groupIndex];

                    return BarTooltipItem(
                      '${_activityLabel(activity)}\n${_valueLabel(activity)}',
                      textTheme.bodySmall!.copyWith(color: colorScheme.onInverseSurface),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) => _buildBottomLabel(
                      value,
                      activities,
                      textTheme,
                      colorScheme,
                      labelStep: labelStep,
                    ),
                    reservedSize: MediaQuery.textScalerOf(context).scale(28),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: MediaQuery.textScalerOf(context).scale(40),
                    interval: yAxis.interval,
                    getTitlesWidget: (value, meta) => _buildYAxisLabel(
                      value,
                      textTheme,
                      colorScheme,
                      metric == ReadingActivityMetric.time ? _formatMinutesLabel : _formatPagesLabel,
                    ),
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yAxis.interval,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: colorScheme.outline.withValues(alpha: 0.7), strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.7)),
                  bottom: BorderSide(color: colorScheme.outline),
                ),
              ),
              barGroups: activities.asMap().entries.map((entry) {
                final index = entry.key;
                final activity = entry.value;

                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: _value(activity),
                      color: activity.isToday ? colorScheme.primary : colorScheme.primary.withValues(alpha: 0.6),
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }).toList(),
            ),
            duration: AppMotion.duration(context, AnimationDurations.standard),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      height: isDesktop ? 200 : 160,
      child: const EmptyState.compact(icon: Icons.bar_chart_outlined, title: 'No reading data for this period'),
    );
  }
}

/// A bar chart displaying books read per month using fl_chart.
class BooksPerMonthChart extends StatelessWidget {
  final List<MonthlyStats> monthlyStats;
  final bool isDesktop;

  const BooksPerMonthChart({super.key, required this.monthlyStats, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (monthlyStats.isEmpty) {
      return _buildEmptyState(context);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final maxBooks = monthlyStats
        .map((item) => item.booksRead)
        .reduce((total, value) => math.max(total, value))
        .toDouble();

    final chartHeight = isDesktop ? 200.0 : 160.0;

    final displayStats = monthlyStats;

    return SizedBox(
      height: chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 50;
          final barWidth = (availableWidth / displayStats.length * 0.5).clamp(8.0, isDesktop ? 28.0 : 22.0);

          return BarChart(
            key: ValueKey(AppMotion.disabled(context)),
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxBooks > 0 ? maxBooks * 1.2 : 5,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => colorScheme.inverseSurface,
                  tooltipRoundedRadius: AppRadius.md,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final stats = displayStats[groupIndex];

                    return BarTooltipItem(
                      '${stats.fullMonthLabel} ${stats.year}\n${stats.booksRead} books',
                      textTheme.bodySmall!.copyWith(color: colorScheme.onInverseSurface),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= displayStats.length) {
                        return const SizedBox.shrink();
                      }

                      final stats = displayStats[value.toInt()];

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${stats.monthLabel} ${stats.year % 100}',
                          style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    },
                    reservedSize: MediaQuery.textScalerOf(context).scale(28),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value == value.truncateToDouble() && value >= 0 && value <= meta.max * 0.95) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${value.toInt()}',
                            style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: colorScheme.outline.withValues(alpha: 0.7), strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: colorScheme.outline)),
              ),
              barGroups: displayStats.asMap().entries.map((entry) {
                final index = entry.key;
                final stats = entry.value;

                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: stats.booksRead.toDouble(),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [colorScheme.secondary, colorScheme.secondary.withValues(alpha: 0.7)],
                      ),
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }).toList(),
            ),
            duration: AppMotion.duration(context, AnimationDurations.standard),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      height: isDesktop ? 200 : 160,
      child: const EmptyState.compact(icon: Icons.bar_chart_outlined, title: 'No books read data available'),
    );
  }
}
