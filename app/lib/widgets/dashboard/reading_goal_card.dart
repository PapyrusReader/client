import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

/// Card displaying the user's reading goals progress.
/// Supports multiple goals displayed in a compact list.
class ReadingGoalCard extends StatelessWidget {
  /// The active reading goals.
  final List<ReadingGoal> goals;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// Whether to use desktop styling.
  final bool isDesktop;

  const ReadingGoalCard({super.key, required this.goals, this.onTap, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return _buildEmptyState(context);
    return _buildCard(context);
  }

  // ============================================================================
  // CARD WITH GOALS
  // ============================================================================

  /// Builds the card showing up to 3 active reading goals.
  Widget _buildCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant, width: BorderWidths.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reading goals', style: textTheme.titleMedium),
              TextButton.icon(
                onPressed: onTap ?? () => context.go('/goals'),
                icon: const Text('View all'),
                label: const Icon(Icons.arrow_forward, size: 16),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          ...goals.take(3).map((goal) => _buildGoalRow(context, goal)),
        ],
      ),
    );
  }

  /// Builds a single goal row with description, progress fraction, and bar.
  Widget _buildGoalRow(BuildContext context, ReadingGoal goal) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  goal.description,
                  style: textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                goal.type == GoalType.minutes
                    ? '${formatDuration(goal.current)}/${formatDuration(goal.target)}'
                    : '${goal.current}/${goal.target}',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: AppLinearProgressIndicator(
              value: goal.progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: goal.isCompleted ? colorScheme.tertiary : colorScheme.primary,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // EMPTY STATE
  // ============================================================================

  /// Builds the empty state when no reading goals are set.
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant, width: BorderWidths.thin),
      ),
      child: EmptyState.compact(
        icon: Icons.flag_outlined,
        title: 'No reading goals set',
        subtitle: 'Set a goal to track your progress',
        action: EmptyStateAction(label: 'Set a goal', onPressed: () => context.go('/goals')),
      ),
    );
  }
}
