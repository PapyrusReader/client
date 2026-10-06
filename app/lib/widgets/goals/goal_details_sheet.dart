import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';

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
      final progress = history == null
          ? widget.provider.progress(goal)
          : projectGoal(
              history.goal,
              widget.provider.store.readingActivities,
              widget.provider.now,
              period: history.range,
            );
      final periods = widget.provider.history.where((period) => period.goal.id == goal.id).toList();
      return AppBottomSheet(
        title: 'Goal details',
        canClose: !_saving,
        onClose: () => Navigator.pop(context),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GoalCard(goal: goal, progress: progress),
            const SizedBox(height: Spacing.lg),
            Text('Calendar timezone: ${goal.timezone}', style: Theme.of(context).textTheme.bodySmall),
            if (widget.historical == null && !goal.isArchived) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => AddGoalSheet.show(context, provider: widget.provider, editing: goal),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit target'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () =>
                              _action(() => widget.provider.pauseGoal(goal.id, goal.isActive, repository: _repository)),
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
              ),
            ],
            if (goal.isArchived && widget.provider.store.getReadingGoal(goal.id) != null)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _action(() => widget.provider.restoreGoal(goal.id, repository: _repository)),
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Restore goal'),
              ),
            const SizedBox(height: Spacing.lg),
            Text('Counted activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (progress.activities.isEmpty)
              const Text('No qualifying reading in this period yet.')
            else
              ...groupReadingActivities(
                progress.activities,
              ).map((activity) => ReadingActivityTile(activity: activity, provider: widget.provider)),
            if (periods.isNotEmpty && widget.historical == null) ...[
              const SizedBox(height: Spacing.lg),
              Text('Previous periods', style: Theme.of(context).textTheme.titleMedium),
              for (final period in periods)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(period.reached ? Icons.check_circle_outline : Icons.event_outlined),
                  title: Text(
                    '${DateFormat.yMMMd().format(GoalCalendar.local(period.range.start, goal.timezone))} – ${DateFormat.yMMMd().format(GoalCalendar.local(period.range.end.subtract(const Duration(microseconds: 1)), goal.timezone))}',
                  ),
                  subtitle: Text('${goalCount(period)} · ${period.reached ? 'Achieved' : 'Missed'}'),
                  onTap: () =>
                      GoalDetailsSheet.show(context, goal: period.goal, provider: widget.provider, historical: period),
                ),
            ],
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
        footer: BottomSheetFormActions(
          onCancel: _saving || widget.provider.store.getReadingGoal(goal.id) == null ? null : _delete,
          cancelLabel: 'Delete goal',
          onSave: _saving ? null : () => Navigator.pop(context),
          saveLabel: 'Done',
        ),
      );
    },
  );
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text('Reading activity and previous periods remain in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete goal')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _action(() => widget.provider.deleteGoal(widget.goal.id, repository: _repository));
    if (mounted && _error == null) Navigator.pop(context);
  }
}
