import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';

/// A day/book row summarizes reading; expanding it keeps every audit entry available.
class ReadingActivityTimeline extends StatelessWidget {
  const ReadingActivityTimeline({
    super.key,
    required this.activities,
    required this.provider,
    required this.timezone,
    this.correctedIds = const {},
    this.range,
  });
  final List<ReadingActivity> activities;
  final GoalsProvider provider;
  final String timezone;
  final Set<String> correctedIds;
  final GoalRange? range;

  @override
  Widget build(BuildContext context) {
    final days = <DateTime, Map<String, List<ReadingActivity>>>{};
    final sorted = [...activities]..sort((a, b) => b.endTime.compareTo(a.endTime));
    for (final entry in sorted) {
      // A reader interval crossing midnight belongs to each exposed day. Keep
      // its original identity so inspecting or correcting it still edits one entry.
      final entryDays = <DateTime>{};
      if (entry.kind == 'reading' && entry.endTime.isAfter(entry.startTime)) {
        var cursor = entry.startTime;
        if (range != null && cursor.isBefore(range!.start)) cursor = range!.start;
        final end = range != null && range!.end.isBefore(entry.endTime) ? range!.end : entry.endTime;
        while (cursor.isBefore(end)) {
          entryDays.add(GoalCalendar.midnight(cursor, timezone));
          cursor = GoalCalendar.nextDay(cursor, timezone);
        }
      } else if (range == null || range!.contains(entry.endTime)) {
        entryDays.add(GoalCalendar.midnight(entry.endTime, timezone));
      }
      for (final day in entryDays) {
        days.putIfAbsent(day, () => {}).putIfAbsent(entry.bookId, () => []).add(entry);
      }
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in (days.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))) ...[
          Padding(
            padding: const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.sm),
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                DateFormat.yMMMEd().format(GoalCalendar.local(day.key, timezone)),
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
                for (final group in day.value.values) ...[
                  if (group != day.value.values.first) const Divider(height: 1),
                  _bookRow(context, day.key, group),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bookRow(BuildContext context, DateTime day, List<ReadingActivity> entries) {
    final book = provider.store.getBook(entries.first.bookId);
    final colors = Theme.of(context).colorScheme;
    final current = entries.where((entry) => !correctedIds.contains(entry.id)).toList();
    final end = GoalCalendar.nextDay(day, timezone);
    final totals = projectGoal(
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
      period: GoalRange(day, end),
    );
    final sources = current.map((entry) => entry.source == 'reader' ? 'Reader' : 'Manual').toSet();
    final summary = [
      if (totals.finishedBooks > 0) 'Finished',
      if (totals.seconds > 0) totals.seconds < 60 ? '${totals.seconds} sec' : formatDuration(totals.seconds ~/ 60),
      if (totals.pages > 0) '${totals.pages.floor()} ${totals.estimated ? 'estimated pages' : 'pages'}',
      ...sources,
      if (entries.any((entry) => correctedIds.contains(entry.id))) 'Corrected entries',
    ].join(' · ');
    final grouped = [
      ...groupReadingActivities(current),
      ...groupReadingActivities(entries.where((entry) => correctedIds.contains(entry.id))),
    ];
    return ExpansionTile(
      key: ValueKey('activity-book-${entries.first.bookId}-${day.toIso8601String()}'),
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
        for (final entry in grouped)
          ReadingActivityTile(
            activity: entry,
            provider: provider,
            corrected: correctedIds.contains(entry.id),
            showBookTitle: false,
          ),
      ],
    );
  }
}
