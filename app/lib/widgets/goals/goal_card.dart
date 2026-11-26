import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/design_tokens.dart';

IconData goalIcon(GoalType type) => switch (type) {
  GoalType.books => Icons.book_outlined,
  GoalType.pages => Icons.menu_book_outlined,
  GoalType.minutes => Icons.schedule_outlined,
  GoalType.days => Icons.calendar_today_outlined,
};
String goalTime(int seconds) {
  if (seconds == 0) {
    return '0 sec';
  }

  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;

  if (minutes == 0) {
    return '$remainder sec';
  }

  return remainder == 0 ? formatDuration(minutes) : '${formatDuration(minutes)} ${remainder}s';
}

String goalCount(GoalProgress progress) =>
    progress.goal.type == GoalType.minutes && !progress.reached && progress.seconds % 60 != 0
    ? '${goalTime(progress.seconds)} of ${formatDuration(progress.goal.targetValue)}'
    : '${progress.value} of ${progress.goal.targetValue} ${progress.goal.unitLabel(progress.goal.targetValue)}';

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({
    super.key,
    required this.goal,
    required this.progress,
    required this.ended,
    required this.countStyle,
  });

  final ReadingGoal goal;
  final GoalProgress? progress;
  final bool ended;
  final TextStyle? countStyle;

  @override
  Widget build(BuildContext context) {
    final count = progress == null
        ? '${goal.currentValue.clamp(0, goal.targetValue)} of ${goal.targetValue} ${goal.unitLabel(goal.targetValue)}'
        : goalCount(progress!);
    final reached = progress?.reached ?? goal.isCompleted;

    final status = switch (goal) {
      _ when goal.isArchived => ('Archived', Icons.archive_outlined),
      _ when !goal.isActive => ('Paused', Icons.pause_circle_outline),
      _ when ended && reached => ('Achieved', Icons.check_circle_outline),
      _ when ended => ('Missed', Icons.event_outlined),
      _ when reached => ('Target reached', Icons.check_circle_outline),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.md,
          runSpacing: Spacing.xs,
          children: [
            ExcludeSemantics(child: Text(count, style: countStyle)),
            if (status != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(status.$2, size: IconSizes.small),
                  const SizedBox(width: Spacing.xs),
                  Flexible(child: Text(status.$1, style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        LinearProgressIndicator(
          value: progress?.fraction ?? goal.progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(AppRadius.full),
          semanticsLabel: '${goal.displayTitle}, $count',
        ),
      ],
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    this.progress,
    this.onTap,
    this.onMenu,
    this.scopeLabel,
    this.isDesktop = false,
    this.fillHeight = false,
    this.showReadingDays = false,
    this.showPeriodDates = false,
  });

  final ReadingGoal goal;
  final GoalProgress? progress;
  final VoidCallback? onTap;
  final void Function(String)? onMenu;
  final String? scopeLabel;
  final bool isDesktop;
  final bool fillHeight;
  final bool showReadingDays;
  final bool showPeriodDates;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final projected = progress?.projected ?? goal;
    final today = GoalCalendar.midnight(DateTime.now(), goal.timezone);
    final expired = progress?.range.end.isAfter(DateTime.now().toUtc()) == false;

    return Card(
      semanticContainer: false,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(goalIcon(goal.type), color: colors.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Tooltip(
                      message: projected.cardTitle,
                      excludeFromSemantics: true,
                      child: Text(
                        projected.cardTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: texts.titleMedium,
                      ),
                    ),
                  ),
                  if (onMenu != null)
                    PopupMenuButton<String>(
                      tooltip: 'Goal actions',
                      onSelected: onMenu,
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit goal')),
                        PopupMenuItem(value: 'pause', child: Text(goal.isActive ? 'Pause' : 'Resume')),
                        const PopupMenuItem(value: 'archive', child: Text('Archive')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              GoalProgressBar(goal: projected, progress: progress, ended: expired, countStyle: texts.titleMedium),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.lg,
                runSpacing: Spacing.sm,
                children: [
                  _metadata(
                    context,
                    icon: projected.isRecurring && !showPeriodDates && !projected.isCustomPeriod
                        ? Icons.repeat
                        : Icons.event_outlined,
                    category: 'Schedule',
                    value: _schedule(projected),
                  ),
                  _metadata(
                    context,
                    icon: switch (goal.scope) {
                      GoalScope.library => Icons.local_library_outlined,
                      GoalScope.book => Icons.menu_book_outlined,
                      GoalScope.shelf => Icons.shelves,
                    },
                    category: 'Scope',
                    value: scopeLabel ?? 'Whole library',
                  ),
                ],
              ),
              if (progress?.estimated == true && goal.type == GoalType.pages)
                Text('Estimated pages included', style: texts.bodySmall),
              if (showReadingDays && goal.type == GoalType.days) ...[
                const SizedBox(height: Spacing.md),
                if (goal.period == GoalPeriod.weekly && progress != null)
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [for (var i = 0; i < 7; i++) _day(context, i, today)],
                  ),
                const SizedBox(height: Spacing.sm),
                Text('${goal.minimumMinutes} minutes qualifies a day', style: texts.bodySmall),
              ],
              if (fillHeight) const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  String _schedule(ReadingGoal projected) {
    if (!showPeriodDates && projected.isRecurring && !projected.isCustomPeriod) {
      return projected.period.label;
    }

    final format = DateFormat.yMMMd();
    final end = format.format(
      GoalCalendar.local(projected.endDate.subtract(const Duration(microseconds: 1)), goal.timezone),
    );

    if (!showPeriodDates) {
      return 'Due $end';
    }

    final start = format.format(GoalCalendar.local(projected.startDate, goal.timezone));
    return start == end ? start : '$start – $end';
  }

  Widget _metadata(BuildContext context, {required IconData icon, required String category, required String value}) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: '$category, $value',
      excludeSemantics: true,
      child: Tooltip(
        message: value,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: IconSizes.small, color: color),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _day(BuildContext context, int index, DateTime today) {
    final start = GoalCalendar.local(progress!.range.start, goal.timezone);
    final localDate = GoalCalendar.dayOffset(start, index, goal.timezone);
    final done = progress!.creditedDays.contains(localDate);
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message:
          '${DateFormat.yMMMd().format(GoalCalendar.local(localDate, goal.timezone))}: ${done ? 'qualified' : 'not qualified'}',
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: done ? colors.secondaryContainer : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: localDate == today ? colors.primary : colors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][index]),
            const SizedBox(height: Spacing.xs),
            Icon(done ? Icons.check : Icons.remove, size: 16),
          ],
        ),
      ),
    );
  }
}
