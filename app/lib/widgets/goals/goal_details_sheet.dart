import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/reading_activity_timeline.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';

class GoalDetailsSheet extends StatefulWidget {
  const GoalDetailsSheet({super.key, required this.goal, required this.provider, this.historical});
  final ReadingGoal goal;
  final GoalsProvider provider;
  final GoalProgress? historical;

  static Future<void> show(
    BuildContext context, {
    required ReadingGoal goal,
    required GoalsProvider provider,
    GoalProgress? historical,
  }) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (_) => GoalDetailsSheet(goal: goal, provider: provider, historical: historical),
  );

  @override
  State<GoalDetailsSheet> createState() => _GoalDetailsSheetState();
}

class _GoalDetailsSheetState extends State<GoalDetailsSheet> {
  late final TrackingRepository? _repository = widget.provider.store.trackingRepository;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.provider,
    builder: (context, _) {
      final goal = widget.provider.store.getReadingGoal(widget.goal.id) ?? widget.goal;
      final history = widget.historical;

      final progress = projectGoal(
        history?.goal ?? goal,
        widget.provider.store.readingActivities,
        widget.provider.now,
        period: history?.range,
        collectContributions: true,
      );

      final hasPreviousPeriods = history == null && widget.provider.periodHistory(goalId: goal.id).isNotEmpty;
      final canRestore = goal.isArchived && widget.provider.store.getReadingGoal(goal.id) != null;
      final colors = Theme.of(context).colorScheme;

      return GoalControls(
        child: AppBottomSheet(
          title: 'Goal details',
          canClose: !_saving,
          onClose: () => Navigator.pop(context),
          contentPadding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.md),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _progressSummary(context, progress),
              if (canRestore || (widget.historical == null && !goal.isArchived)) ...[
                const SizedBox(height: Spacing.md),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    if (canRestore)
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _action(() => widget.provider.restoreGoal(goal.id, repository: _repository)),
                        icon: const Icon(Icons.unarchive_outlined),
                        label: const Text('Restore goal'),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => AddGoalSheet.show(context, provider: widget.provider, editing: goal),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit goal'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _action(
                                () => widget.provider.pauseGoal(goal.id, goal.isActive, repository: _repository),
                              ),
                        icon: Icon(goal.isActive ? Icons.pause : Icons.play_arrow),
                        label: Text(goal.isActive ? 'Pause goal' : 'Resume goal'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _action(() => widget.provider.archiveGoal(goal.id, repository: _repository)),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Archive goal'),
                      ),
                    ],
                  ],
                ),
              ],
              SizedBox(height: progress.contributionsByDay.isEmpty ? Spacing.md : Spacing.sm),
              if (progress.contributionsByDay.isEmpty)
                Card.outlined(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: EmptyState.compact(
                    icon: Icons.auto_stories_outlined,
                    iconSize: IconSizes.medium,
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.lg),
                    title: switch (progress.goal.type) {
                      GoalType.books => 'No books finished yet',
                      GoalType.pages => 'No pages counted yet',
                      GoalType.minutes => 'No reading time yet',
                      GoalType.days => 'No qualifying reading days yet',
                    },
                  ),
                )
              else ...[
                if (goal.type == GoalType.minutes || goal.type == GoalType.days) ...[
                  if (progress.hasCreationCutoff || progress.hasOverlappingTime)
                    Text(
                      [
                        if (progress.hasCreationCutoff) 'Time before goal creation is excluded.',
                        if (progress.hasOverlappingTime) 'Overlapping time is counted once.',
                      ].join(' '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                ReadingActivityTimeline(
                  activities: progress.activities,
                  provider: widget.provider,
                  timezone: goal.timezone,
                  range: progress.range,
                  goalProgress: progress,
                ),
              ],
              if (hasPreviousPeriods)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Previous periods'),
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.pushNamed('GOAL_HISTORY', queryParameters: {'goal': goal.id});
                    },
                  ),
                ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          footer: BottomSheetFormActions(
            equalWidths: true,
            onCancel: _saving || widget.provider.store.getReadingGoal(goal.id) == null ? null : _delete,
            cancelLabel: 'Delete',
            onSave: _saving ? null : () => Navigator.pop(context),
            saveLabel: 'Done',
          ),
        ),
      );
    },
  );

  Widget _progressSummary(BuildContext context, GoalProgress progress) {
    final goal = progress.projected;
    final texts = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final ended = !progress.range.end.isAfter(widget.provider.now);

    final scope = switch (goal.scope) {
      GoalScope.library => 'Whole library',
      GoalScope.book =>
        goal.selectedBookIds.length > 1
            ? goal.selectedBookIds.map((id) => widget.provider.store.getBook(id)?.title ?? 'Removed book').join(', ')
            : widget.provider.store.getBook(goal.scopeId!)?.title ?? 'Removed book',
      GoalScope.shelf => widget.provider.store.getShelf(goal.scopeId!)?.name ?? 'Removed shelf',
    };

    final start = GoalCalendar.local(progress.range.start, goal.timezone);
    final end = GoalCalendar.local(progress.range.end.subtract(const Duration(microseconds: 1)), goal.timezone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(goalIcon(goal.type), color: colors.primary),
            const SizedBox(width: Spacing.sm),
            Expanded(child: Text(goal.displayTitle, style: texts.titleLarge)),
          ],
        ),
        const SizedBox(height: Spacing.md),
        GoalProgressBar(goal: goal, progress: progress, ended: ended, countStyle: texts.headlineSmall),
        const SizedBox(height: Spacing.md),
        Text(scope, style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: Spacing.xs),
        Text(
          '${DateFormat.yMMMd().format(start)} – ${DateFormat.yMMMd().format(end)}',
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (progress.estimated && goal.type == GoalType.pages) ...[
          const SizedBox(height: Spacing.xs),
          Text('Estimated pages included', style: texts.bodySmall),
        ],
        if (goal.type == GoalType.days) ...[
          const SizedBox(height: Spacing.md),
          if (goal.period == GoalPeriod.weekly)
            Wrap(
              spacing: Spacing.lg,
              runSpacing: Spacing.sm,
              children: [
                for (var i = 0; i < 7; i++)
                  _readingDay(context, progress, GoalCalendar.dayOffset(progress.range.start, i, goal.timezone)),
              ],
            ),
          const SizedBox(height: Spacing.sm),
          Text('Daily minimum: ${goal.minimumMinutes} minutes', style: texts.bodySmall),
        ],
      ],
    );
  }

  Widget _readingDay(BuildContext context, GoalProgress progress, DateTime day) {
    final date = GoalCalendar.local(day, progress.goal.timezone);
    final qualified = progress.creditedDays.contains(day);

    return Semantics(
      label: '${DateFormat.yMMMd().format(date)}: ${qualified ? 'Reading day' : 'Daily minimum not reached'}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat.E().format(date), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Spacing.xs),
          Icon(qualified ? Icons.check : Icons.remove, size: IconSizes.small),
        ],
      ),
    );
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await action();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmGoalDeletion(context);

    if (confirmed != true || !mounted) {
      return;
    }

    await _action(() => widget.provider.deleteGoal(widget.goal.id, repository: _repository));

    if (mounted && _error == null) {
      Navigator.pop(context);
    }
  }
}

Future<bool> confirmGoalDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text('Reading activity and previous periods remain in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;
