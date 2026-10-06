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
    this.fillHeight = false,
    this.bookProgressLabel,
    this.showReadingDays = false,
  });
  final ReadingGoal goal;
  final GoalProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onContinue;
  final void Function(String)? onMenu;
  final String? scopeLabel;
  final bool isDesktop;
  final bool fillHeight;
  final String? bookProgressLabel;
  final bool showReadingDays;
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
                      message: projected.displayTitle,
                      excludeFromSemantics: true,
                      child: Text(
                        projected.displayTitle,
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
              Text(
                '${projected.currentValue} / ${projected.targetValue} ${projected.typeLabel}',
                style: texts.titleMedium,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                goal.isRecurring
                    ? projected.periodLabel
                    : 'Until ${DateFormat.yMMMd().format(GoalCalendar.local(projected.endDate.subtract(const Duration(microseconds: 1)), goal.timezone))}',
                style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              Semantics(
                container: true,
                label:
                    '${projected.displayTitle}, ${projected.currentValue} of ${projected.targetValue} ${projected.typeLabel}',
                child: LinearProgressIndicator(
                  value: progress?.fraction ?? projected.progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (state != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          projected.isCompleted
                              ? Icons.check_circle_outline
                              : goal.isActive
                              ? Icons.event_outlined
                              : Icons.pause_circle_outline,
                          size: 16,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Flexible(child: Text(state, style: texts.bodySmall)),
                      ],
                    )
                  else
                    Text(
                      '${((progress?.fraction ?? projected.progress) * 100).round()}% complete',
                      style: texts.bodySmall,
                    ),
                  if (!projected.isCompleted) Text(projected.statusText, style: texts.bodySmall),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Tooltip(
                message: scopeLabel ?? 'Whole library',
                excludeFromSemantics: true,
                child: Text(
                  scopeLabel ?? 'Whole library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              if (progress?.estimated == true && goal.type == GoalType.pages)
                Text('Estimated pages included', style: texts.bodySmall),
              if (bookProgressLabel != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(bookProgressLabel!, style: texts.bodySmall),
              ],
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
              if (onContinue != null && !expired && !goal.isArchived && goal.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
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
