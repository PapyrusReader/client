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
String goalCount(GoalProgress progress) =>
    '${progress.value} / ${progress.goal.targetValue} ${progress.goal.typeLabel}';

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    this.progress,
    this.onTap,
    this.onContinue,
    this.onMenu,
    this.scopeLabel,
    this.isDesktop = false,
  });
  final ReadingGoal goal;
  final GoalProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onContinue;
  final void Function(String)? onMenu;
  final String? scopeLabel;
  final bool isDesktop;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final projected = progress?.projected ?? goal;
    final today = GoalCalendar.midnight(DateTime.now(), goal.timezone);
    final expired = progress?.range.end.isAfter(DateTime.now().toUtc()) == false;
    final state = projected.isArchived
        ? 'Archived'
        : !projected.isActive
        ? 'Paused'
        : expired
        ? projected.isCompleted
              ? 'Achieved'
              : 'Missed'
        : projected.isCompleted
        ? 'Target reached'
        : null;
    return Card(
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(goalIcon(goal.type), color: colors.primary),
                  const SizedBox(width: Spacing.sm),
                  Expanded(child: Text(projected.displayTitle, style: texts.titleMedium)),
                  if (onMenu != null)
                    PopupMenuButton<String>(
                      tooltip: 'Goal actions',
                      onSelected: onMenu,
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit target')),
                        PopupMenuItem(value: 'pause', child: Text(goal.isActive ? 'Pause' : 'Resume')),
                        const PopupMenuItem(value: 'archive', child: Text('Archive')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                '${projected.currentValue} / ${projected.targetValue} ${projected.typeLabel}',
                style: texts.titleLarge,
              ),
              const SizedBox(height: Spacing.sm),
              Semantics(
                label:
                    '${projected.displayTitle}, ${projected.currentValue} of ${projected.targetValue} ${projected.typeLabel}',
                child: LinearProgressIndicator(
                  value: progress?.fraction ?? projected.progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (state != null)
                Row(
                  children: [
                    Icon(
                      projected.isCompleted
                          ? Icons.check_circle_outline
                          : goal.isActive
                          ? Icons.event_outlined
                          : Icons.pause_circle_outline,
                      size: 18,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: Text(state, style: texts.bodyMedium)),
                  ],
                )
              else
                Text(projected.statusText, style: texts.bodyMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                '${scopeLabel ?? 'Whole library'} · ${goal.isRecurring ? projected.periodLabel : 'Until ${DateFormat.yMMMd().format(GoalCalendar.local(projected.endDate.subtract(const Duration(microseconds: 1)), goal.timezone))}'}${progress?.estimated == true && goal.type == GoalType.pages ? ' · Estimated pages included' : ''}',
                style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (goal.type == GoalType.days) ...[
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
              if (onContinue != null && !expired && !goal.isArchived && goal.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: onContinue,
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('Continue reading'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _day(BuildContext context, int index, DateTime today) {
    final start = GoalCalendar.local(progress!.range.start, goal.timezone);
    final localDate = GoalCalendar.dayOffset(start, index, goal.timezone);
    final done = progress!.qualifiedDays.contains(localDate);
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
