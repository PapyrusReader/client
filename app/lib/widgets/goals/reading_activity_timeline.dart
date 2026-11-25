import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/goals/activity_pagination.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';

/// Pages through daily book totals, with session and manual log details on demand.
class ReadingActivityTimeline extends StatefulWidget {
  const ReadingActivityTimeline({
    super.key,
    required this.activities,
    required this.provider,
    required this.timezone,
    this.correctedIds = const {},
    this.range,
    this.goalProgress,
  });

  final List<ReadingActivity> activities;
  final GoalsProvider provider;
  final String timezone;
  final Set<String> correctedIds;
  final GoalRange? range;
  final GoalProgress? goalProgress;

  @override
  State<ReadingActivityTimeline> createState() => _ReadingActivityTimelineState();
}

class _ReadingActivityTimelineState extends State<ReadingActivityTimeline> {
  static const _pageSize = 10;
  int _page = 0;

  late var _groups = _groupByDayAndBook();

  @override
  void didUpdateWidget(ReadingActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.activities != widget.activities ||
        oldWidget.timezone != widget.timezone ||
        oldWidget.range?.start != widget.range?.start ||
        oldWidget.range?.end != widget.range?.end) {
      _groups = _groupByDayAndBook();
    }
  }

  List<(DateTime, List<ReadingActivity>)> _groupByDayAndBook() {
    final timezone = widget.timezone;
    final range = widget.range;
    final days = <DateTime, Map<String, List<ReadingActivity>>>{};
    final contributions = widget.goalProgress?.contributionsByDay;

    if (contributions != null) {
      for (final day in contributions.entries) {
        final books = days[day.key] = {};

        for (final entry in day.value.reversed) {
          books.putIfAbsent(entry.bookId, () => []).add(entry);
        }
      }

      return _bookGroups(days);
    }

    final sorted = [...widget.activities]
      ..sort((left, right) {
        final time = right.endTime.compareTo(left.endTime);
        return time != 0 ? time : left.id.compareTo(right.id);
      });

    for (final entry in sorted) {
      // A reader interval crossing midnight belongs to each exposed day. Keep
      // its original identity so inspecting or correcting it still edits one entry.
      final entryDays = <DateTime>{};

      if (entry.kind == 'reading' && entry.endTime.isAfter(entry.startTime)) {
        var cursor = entry.startTime;

        if (range != null && cursor.isBefore(range.start)) {
          cursor = range.start;
        }

        final end = range != null && range.end.isBefore(entry.endTime) ? range.end : entry.endTime;

        while (cursor.isBefore(end)) {
          entryDays.add(GoalCalendar.midnight(cursor, timezone));
          cursor = GoalCalendar.nextDay(cursor, timezone);
        }
      } else if (range == null || range.contains(entry.endTime)) {
        entryDays.add(GoalCalendar.midnight(entry.endTime, timezone));
      }

      for (final day in entryDays) {
        days.putIfAbsent(day, () => {}).putIfAbsent(entry.bookId, () => []).add(entry);
      }
    }

    return _bookGroups(days);
  }

  List<(DateTime, List<ReadingActivity>)> _bookGroups(Map<DateTime, Map<String, List<ReadingActivity>>> days) {
    final dates = days.keys.toList()..sort((left, right) => right.compareTo(left));

    return [
      for (final day in dates)
        for (final entries in days[day]!.values) (day, entries),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = (_groups.length / _pageSize).ceil();
    final page = _page.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
    final visible = _groups.skip(page * _pageSize).take(_pageSize);
    final pageDays = <DateTime, List<List<ReadingActivity>>>{};

    for (final (day, entries) in visible) {
      pageDays.putIfAbsent(day, () => []).add(entries);
    }

    final colors = Theme.of(context).colorScheme;
    final pagination = pageCount > 1
        ? ActivityPagination(page: page, pageCount: pageCount, onChanged: _changePage)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pagination != null && widget.goalProgress != null) pagination,
        for (final (index, day) in pageDays.entries.indexed) ...[
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 && widget.goalProgress != null ? Spacing.xs : Spacing.lg,
              bottom: Spacing.sm,
            ),
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                DateFormat.yMMMEd().format(GoalCalendar.local(day.key, widget.timezone)),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final group in day.value) ...[
                  if (group != day.value.first) const Divider(height: 1),
                  _bookRow(context, day.key, group),
                ],
              ],
            ),
          ),
        ],
        if (pagination != null && widget.goalProgress == null) ...[
          const SizedBox(height: Spacing.md),
          pagination,
        ],
      ],
    );
  }

  void _changePage(int page) {
    setState(() => _page = page);

    if (widget.goalProgress == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.maybeOf(context, axis: Axis.vertical)?.position.ensureVisible(context.findRenderObject()!);
        }
      });
    }
  }

  Widget _bookRow(BuildContext context, DateTime day, List<ReadingActivity> entries) {
    final provider = widget.provider;
    final timezone = widget.timezone;
    final correctedIds = widget.correctedIds;
    final book = provider.store.getBook(entries.first.bookId);
    final colors = Theme.of(context).colorScheme;
    final current = entries.where((entry) => !correctedIds.contains(entry.id)).toList();
    final end = GoalCalendar.nextDay(day, timezone);

    final totals = projectGoal(
      widget.goalProgress?.goal ??
          ReadingGoal(
            id: 'timeline',
            type: GoalType.minutes,
            targetValue: 1,
            period: GoalPeriod.custom,
            createdAt: day,
            startDate: day,
            endDate: end,
            timezone: timezone,
            isRecurring: false,
          ),
      current,
      provider.now,
      period: GoalRange(
        widget.range != null && widget.range!.start.isAfter(day) ? widget.range!.start : day,
        widget.range != null && widget.range!.end.isBefore(end) ? widget.range!.end : end,
      ),
    );

    final progress = widget.goalProgress;
    final metric = progress?.goal.type;
    final dayRange = GoalRange(day, end);
    final seconds = progress?.secondsForDay(current, dayRange) ?? totals.seconds;
    final pages = metric == GoalType.pages
        ? current.fold(0.0, (total, entry) => total + progress!.pagesFor(entry))
        : totals.pages;

    final summary = [
      if ((metric == null || metric == GoalType.books) && totals.finishedBooks > 0) 'Finished',
      if ((metric == null || metric == GoalType.minutes || metric == GoalType.days) && seconds > 0)
        seconds < 60 ? '$seconds sec' : formatDuration(seconds ~/ 60),
      if ((metric == null || metric == GoalType.pages) && pages > 0) _pageLabel(pages, estimated: totals.estimated),
      if (entries.any((entry) => correctedIds.contains(entry.id))) 'Corrected entries',
    ].join(' · ');

    return ExpansionTile(
      // Expansion state must not share the enclosing list's saved scroll offset.
      key: PageStorageKey('activity-book-${entries.first.bookId}-${day.toIso8601String()}'),
      tilePadding: const EdgeInsets.all(Spacing.md),
      childrenPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: SizedBox(
        width: 36,
        height: 54,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: CoverImage(
            bookId: book?.id,
            imageUrl: book?.coverUrl,
            mediaId: book?.coverMediaId,
            placeholder: ColoredBox(
              color: colors.primaryContainer,
              child: Icon(
                totals.finishedBooks > 0 ? Icons.check : Icons.menu_book_outlined,
                color: colors.onPrimaryContainer,
                size: 20,
              ),
            ),
          ),
        ),
      ),
      title: Tooltip(
        message: entries.first.bookTitle,
        excludeFromSemantics: true,
        child: Text(
          entries.first.bookTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Text(summary.isEmpty ? 'Reading activity' : summary),
      ),
      children: [
        Builder(
          builder: (context) {
            final grouped = [
              ...groupReadingActivities(current, groupUnidentifiedReaderEntries: true),
              ...groupReadingActivities(
                entries.where((entry) => correctedIds.contains(entry.id)),
                groupUnidentifiedReaderEntries: true,
              ),
            ];

            return Column(
              children: [
                for (final entry in grouped)
                  ReadingActivityTile(
                    activity: entry,
                    provider: provider,
                    corrected: correctedIds.contains(entry.id),
                    showBookTitle: false,
                    metricSummary: metric == GoalType.pages
                        ? _pageLabel(progress!.pagesFor(entry), estimated: entry.isEstimated)
                        : null,
                    contributionLabel: _contributionLabel(entry, dayRange),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _pageLabel(double pages, {required bool estimated}) {
    final whole = pages.floor();
    final unit = whole <= 1 ? 'page' : 'pages';
    return '${whole == 0 ? '<1' : whole} ${estimated ? 'estimated $unit' : unit}';
  }

  String? _contributionLabel(ReadingActivity activity, GoalRange day) {
    final progress = widget.goalProgress;

    if (progress == null ||
        activity.kind != 'reading' ||
        (progress.goal.type != GoalType.minutes && progress.goal.type != GoalType.days)) {
      return null;
    }

    final eligible = progress.secondsForDay([activity], day);
    return eligible == activity.seconds ? null : '${goalTime(eligible)} for this goal';
  }
}
