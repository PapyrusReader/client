import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/reading_activity_calendar.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/design_tokens.dart';

class ReadingActivityHeatmap extends StatefulWidget {
  const ReadingActivityHeatmap({
    super.key,
    required this.activities,
    required this.year,
    required this.timezone,
    required this.now,
    required this.onYearChanged,
    required this.onDaySelected,
    this.selectedDay,
  });
  final List<ReadingActivity> activities;
  final int year;
  final String timezone;
  final DateTime now;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<DateTime> onDaySelected;
  final DateTime? selectedDay;
  @override
  State<ReadingActivityHeatmap> createState() => _ReadingActivityHeatmapState();
}

class _ReadingActivityHeatmapState extends State<ReadingActivityHeatmap> {
  final _scroll = ScrollController();
  bool _positionPending = true;
  double? _lastStride;
  @override
  void didUpdateWidget(ReadingActivityHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.timezone != widget.timezone) _positionPending = true;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(ColorScheme colors, int level) => level == 0
      ? colors.surfaceContainerHighest
      : Color.lerp(colors.surface, colors.primary, <double>[0, .25, .45, .7, 1][level])!;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final range = GoalCalendar.calendarPeriod(GoalPeriod.yearly, DateTime.utc(widget.year, 1, 2), widget.timezone);
    final first = range.start;
    final activity = readingActivityCalendar(
      widget.activities,
      range: range,
      timezone: widget.timezone,
      now: widget.now,
    );
    final firstLocal = GoalCalendar.local(first, widget.timezone);
    final gridStart = GoalCalendar.dayOffset(first, 1 - firstLocal.weekday, widget.timezone);
    final dayCount = DateTime.utc(widget.year + 1).difference(DateTime.utc(widget.year)).inDays;
    final columns = ((firstLocal.weekday - 1 + dayCount) / 7).ceil();
    final currentYear = GoalCalendar.local(widget.now, widget.timezone).year;
    final years = <int>{
      currentYear,
      widget.year,
      for (final a in widget.activities) GoalCalendar.local(a.startTime, widget.timezone).year,
    }.where((year) => year <= currentYear).toList()..sort((a, b) => b.compareTo(a));
    return Container(
      key: const Key('reading-activity-heatmap'),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              children: [
                Semantics(container: true, header: true, child: Text('Reading activity', style: texts.titleLarge)),
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(80).clamp(112, 200).toDouble(),
                  child: Semantics(
                    container: true,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('activity-year-${widget.year}'),
                      initialValue: widget.year,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Year', isDense: true),
                      items: [for (final year in years) DropdownMenuItem(value: year, child: Text('$year'))],
                      onChanged: (year) {
                        if (year != null) widget.onYearChanged(year);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 3.0;
                final labelWidth = MediaQuery.textScalerOf(context).scale(24);
                final labelPainter = TextPainter(
                  text: TextSpan(text: 'M', style: texts.labelSmall),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final minCell = math.max(11.0, labelPainter.height + 2 - gap);
                labelPainter.dispose();
                final cell = ((constraints.maxWidth - labelWidth) / columns - gap)
                    .clamp(minCell, math.max(20.0, minCell))
                    .toDouble();
                final stride = cell + gap;
                if (_lastStride != stride) {
                  _lastStride = stride;
                  _positionPending = true;
                }
                if (_positionPending) {
                  _positionPending = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_scroll.hasClients) return;
                    final today = GoalCalendar.local(widget.now, widget.timezone);
                    final visibleDay = widget.year == today.year
                        ? DateTime.utc(today.year, today.month, today.day)
                        : DateTime.utc(widget.year, 12, 31);
                    final week =
                        (visibleDay.difference(DateTime.utc(widget.year)).inDays + firstLocal.weekday - 1) ~/ 7;
                    _scroll.jumpTo(
                      (labelWidth + (week + 1) * stride - constraints.maxWidth).clamp(
                        0,
                        _scroll.position.maxScrollExtent,
                      ),
                    );
                  });
                }
                final headingHeight = MediaQuery.textScalerOf(context).scale(20);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Column(
                        children: [
                          SizedBox(height: headingHeight),
                          for (var day = 0; day < 7; day++)
                            SizedBox(
                              height: stride,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: day.isEven
                                    ? Text(['M', '', 'W', '', 'F', '', 'S'][day], style: texts.labelSmall)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(constraints.maxWidth - labelWidth, columns * stride),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: headingHeight,
                                  child: Row(
                                    children: [
                                      for (var week = 0; week < columns; week++)
                                        SizedBox(
                                          width: stride,
                                          child: OverflowBox(
                                            alignment: AlignmentDirectional.centerStart,
                                            maxWidth: 64,
                                            child: _monthLabel(week, gridStart, texts),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var week = 0; week < columns; week++)
                                      Column(
                                        children: [
                                          for (var weekday = 0; weekday < 7; weekday++)
                                            Padding(
                                              padding: const EdgeInsets.only(right: gap, bottom: gap),
                                              child: _day(
                                                context,
                                                GoalCalendar.dayOffset(gridStart, week * 7 + weekday, widget.timezone),
                                                range,
                                                activity,
                                                cell,
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: Spacing.sm,
              spacing: Spacing.md,
              children: [
                Tooltip(
                  message: 'Dates use ${widget.timezone.replaceAll('_', ' ')}',
                  excludeFromSemantics: true,
                  child: Text(
                    '${activity.length} active ${activity.length == 1 ? 'day' : 'days'}',
                    style: texts.bodySmall,
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: Spacing.xs,
                  children: [
                    Text('Less', style: texts.labelSmall),
                    const SizedBox(width: Spacing.sm),
                    for (var level = 0; level < 5; level++)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: _color(colors, level),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                        ),
                      ),
                    const SizedBox(width: Spacing.xs),
                    Text('More', style: texts.labelSmall),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _monthLabel(int week, DateTime start, TextTheme texts) {
    final date = GoalCalendar.local(GoalCalendar.dayOffset(start, week * 7, widget.timezone), widget.timezone);
    if (date.year != widget.year || (date.day > 7 && week != 0)) return null;
    return Text(DateFormat.MMM().format(date), style: texts.labelSmall);
  }

  Widget _day(
    BuildContext context,
    DateTime day,
    GoalRange range,
    Map<DateTime, ReadingActivityDay> activity,
    double size,
  ) {
    final colors = Theme.of(context).colorScheme;
    final inRange = range.contains(day);
    final future = day.isAfter(widget.now);
    final value = activity[day];
    final seconds = value?.seconds ?? 0;
    final duration = seconds == 0
        ? value?.hasActivity == true
              ? 'Reading logged'
              : 'No reading'
        : seconds < 60
        ? '$seconds sec'
        : '${seconds ~/ 60} min';
    final label =
        '${DateFormat.yMMMd().format(GoalCalendar.local(day, widget.timezone))}: ${future ? 'Future date' : duration}';
    return SizedBox(
      width: size,
      height: size,
      child: inRange
          ? Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: Semantics(
                label: label,
                excludeSemantics: true,
                onTap: future ? null : () => widget.onDaySelected(day),
                button: !future,
                selected: widget.selectedDay == day,
                // Paint inside the scrollable, so offscreen cells cannot cover
                // the fixed weekday labels. Each cell also owns its focus/ripple.
                child: Material(
                  animationDuration: Duration.zero,
                  color: future ? colors.surface : _color(colors, value?.level ?? 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                    side: BorderSide(
                      color: widget.selectedDay == day ? colors.primary : colors.outlineVariant,
                      width: widget.selectedDay == day ? 2 : .5,
                    ),
                  ),
                  child: InkWell(
                    onTap: future ? null : () => widget.onDaySelected(day),
                    borderRadius: BorderRadius.circular(2),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
