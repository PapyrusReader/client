import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/activity_pagination.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/goal_history_filters.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:provider/provider.dart';

enum _GoalSection {
  inProgress('In progress', 'No goals in progress', Icons.auto_stories_outlined),
  notStarted('Not started', 'No goals pending', Icons.bookmark_border),
  completed('Completed', 'No completed goals yet', Icons.task_alt),
  paused('Paused', 'No paused goals', Icons.pause_circle_outline);

  const _GoalSection(this.title, this.emptyMessage, this.icon);
  final String title;
  final String emptyMessage;
  final IconData icon;
}

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key, this.now}) : history = false, goalId = null;
  const GoalsPage.history({super.key, this.now, this.goalId}) : history = true;

  final bool history;
  final String? goalId;
  final DateTime Function()? now;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  late final _provider = GoalsProvider(now: widget.now);
  GoalType? _historyType;
  DateTimeRange? _historyDates;
  final _historyScroll = ScrollController();
  static const _periodPageSize = 10;
  int _periodPage = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider.attach(context.watch<DataStore>());
  }

  @override
  void dispose() {
    _historyScroll.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = libraryPageHorizontalPadding(context);

    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) => GoalControls(
        child: Scaffold(
          floatingActionButton: !widget.history && _usesFab(context)
              ? FloatingActionButton(
                  tooltip: 'New goal',
                  onPressed: () => AddGoalSheet.show(context, provider: _provider),
                  child: const Icon(Icons.add),
                )
              : null,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.history)
                  LibraryPageHeader(
                    title: 'Goal history',
                    leading: BackButton(onPressed: () => context.pop()),
                    compact: _usesFab(context),
                  )
                else
                  _toolbar(context),
                Expanded(child: _content(context, padding)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double padding) {
    if (!_provider.store.isLoaded && _provider.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Waiting for your library',
        subtitle: _provider.error!,
      );
    }

    final insets = EdgeInsets.fromLTRB(
      padding,
      Spacing.lg,
      padding,
      padding + (!widget.history && _usesFab(context) ? Spacing.fabClearance : 0),
    );

    final children = [
      if (_provider.isLoading)
        const Center(child: AppCircularProgressIndicator())
      else if (widget.history)
        ..._history(context)
      else
        ..._overview(context),
      if (_provider.error != null) Text(_provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ];

    if (widget.history) {
      return SingleChildScrollView(
        controller: _historyScroll,
        padding: insets,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }

    return ListView(padding: insets, children: children);
  }

  bool _usesFab(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

  Widget _toolbar(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final useFab = _usesFab(context);
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
      final compact = useFab || constraints.maxWidth < 640 || largeText;

      return Theme(
        data: theme.copyWith(
          materialTapTargetSize: useFab ? theme.materialTapTargetSize : MaterialTapTargetSize.shrinkWrap,
        ),
        child: LibraryCollectionHeader(
          title: 'Goals',
          actions: [
            if (compact)
              IconButton(
                onPressed: () => context.pushNamed('GOAL_HISTORY'),
                tooltip: 'Goal history',
                icon: const Icon(Icons.history),
              )
            else
              TextButton.icon(
                onPressed: () => context.pushNamed('GOAL_HISTORY'),
                icon: const Icon(Icons.history),
                label: const Text('Goal history'),
              ),
            if (compact)
              IconButton(
                tooltip: 'Log reading',
                onPressed: () => LogReadingSheet.show(context, provider: _provider),
                icon: const Icon(Icons.edit_outlined),
              )
            else
              OutlinedButton.icon(
                onPressed: () => LogReadingSheet.show(context, provider: _provider),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Log reading'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, TouchTargets.desktopRecommended),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                  visualDensity: VisualDensity.standard,
                  textStyle: Theme.of(context).textTheme.labelLarge,
                  shape: const StadiumBorder(),
                ),
              ),
            if (!useFab)
              if (compact)
                IconButton.filled(
                  tooltip: 'New goal',
                  onPressed: () => AddGoalSheet.show(context, provider: _provider),
                  icon: const Icon(Icons.add),
                )
              else
                LibraryAddButton(
                  label: 'New goal',
                  onPressed: () => AddGoalSheet.show(context, provider: _provider),
                ),
          ],
        ),
      );
    },
  );

  List<Widget> _overview(BuildContext context) {
    // Recurrence describes a goal's schedule; activity determines its place here.
    final groups = {for (final section in _GoalSection.values) section: <GoalProgress>[]};

    for (final progress in _provider.current) {
      final status = switch (!progress.projected.isActive) {
        true => _GoalSection.paused,
        false when progress.reached => _GoalSection.completed,
        false when progress.fraction > 0 => _GoalSection.inProgress,
        false => _GoalSection.notStarted,
      };

      groups[status]!.add(progress);
    }

    for (final goals in groups.values) {
      goals.sort((left, right) {
        final progress = right.fraction.compareTo(left.fraction);

        if (progress != 0) {
          return progress;
        }

        final deadline = left.range.end.compareTo(right.range.end);

        if (deadline != 0) {
          return deadline;
        }

        final created = left.goal.createdAt.compareTo(right.goal.createdAt);
        return created != 0 ? created : left.goal.id.compareTo(right.goal.id);
      });
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sectionTitle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final emptySurface = BoxDecoration(
      color: Color.alphaBlend(colors.onSurface.withValues(alpha: 0.05), colors.surface),
      borderRadius: BorderRadius.circular(AppRadius.card),
    );

    return [
      for (final group in groups.entries)
        Padding(
          key: ValueKey('goal-section-${group.key.title}'),
          padding: const EdgeInsets.only(bottom: Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(group.key.title, style: sectionTitle)),
              const SizedBox(height: Spacing.sm),
              if (group.value.isNotEmpty)
                _cards(context, group.value)
              else
                DecoratedBox(
                  decoration: emptySurface,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(group.key.icon, size: IconSizes.small, color: colors.onSurfaceVariant),
                        const SizedBox(width: Spacing.sm),
                        Flexible(
                          child: Text(
                            group.key.emptyMessage,
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _cards(
    BuildContext context,
    List<GoalProgress> goals, {
    bool historical = false,
    bool currentDetails = false,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 && MediaQuery.textScalerOf(context).scale(16) <= 24 ? 2 : 1;

      Widget card(GoalProgress progress) => GoalCard(
        key: ValueKey('goal-card-${progress.goal.id}${historical ? '-${progress.range.start.toIso8601String()}' : ''}'),
        fillHeight: columns == 2,
        goal: progress.goal,
        progress: progress,
        showPeriodDates: historical && !currentDetails,
        scopeLabel: _scopeLabel(progress.goal),
        onTap: () => GoalDetailsSheet.show(
          context,
          goal: progress.goal,
          provider: _provider,
          historical: historical && !currentDetails ? progress : null,
        ),
        onMenu: historical ? null : (action) => _goalAction(progress.goal, action),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < goals.length; i += columns) ...[
            if (i > 0) const SizedBox(height: Spacing.md),
            if (columns == 1)
              card(goals[i])
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: card(goals[i])),
                    const SizedBox(width: Spacing.md),
                    Expanded(child: i + 1 < goals.length ? card(goals[i + 1]) : const SizedBox()),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );

  String _scopeLabel(ReadingGoal goal) => switch (goal.scope) {
    GoalScope.library => 'Whole library',
    GoalScope.book =>
      goal.selectedBookIds.length > 1
          ? '${goal.selectedBookIds.length} selected books'
          : _provider.store.getBook(goal.scopeId!)?.title ?? 'Removed book',
    GoalScope.shelf => _provider.store.getShelf(goal.scopeId!)?.name ?? 'Removed shelf',
  };

  List<Widget> _history(BuildContext context) {
    final definitions = _provider.historyDefinitions;
    final goalId = widget.goalId;
    final selected = definitions[goalId];
    final dates = goalDateRange(_historyDates, selected?.timezone ?? GoalCalendar.systemTimezone);
    final periods = _provider.periodHistory(
      goalId: goalId,
      type: _historyType,
      dates: dates,
      includeArchived: goalId != null,
    );
    final archived = <({ReadingGoal goal, GoalRange range})>[];

    if (goalId == null) {
      for (final goal in _provider.completedGoals) {
        if (_historyType != null && goal.type != _historyType) {
          continue;
        }

        final range = GoalCalendar.currentPeriod(goal, _provider.now);

        if (dates == null || range.start.isBefore(dates.end) && range.end.isAfter(dates.start)) {
          archived.add((goal: goal, range: range));
        }
      }
    }

    archived.sort((left, right) {
      final byDate = right.range.end.compareTo(left.range.end);
      return byDate != 0 ? byDate : left.goal.id.compareTo(right.goal.id);
    });

    final periodCount = periods.length;
    final pageCount = ((periodCount + archived.length) / _periodPageSize).ceil();
    final page = _periodPage.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
    final offset = page * _periodPageSize;
    final visiblePeriods = periods.skip(offset).take(_periodPageSize).toList();
    final visibleArchived = archived
        .skip((offset - periodCount).clamp(0, archived.length))
        .take(_periodPageSize - visiblePeriods.length)
        .map((entry) => _provider.progress(entry.goal))
        .toList();

    return [
      if (definitions.isNotEmpty || goalId != null) ...[
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (goalId != null)
              InputChip(
                label: Text(selected?.displayTitle ?? 'Removed goal', overflow: TextOverflow.ellipsis),
                deleteButtonTooltipMessage: 'Show all goals',
                onDeleted: () {
                  setState(() => _periodPage = 0);
                  context.replaceNamed('GOAL_HISTORY');
                },
              )
            else
              GoalTypeFilter(
                selected: _historyType,
                onChanged: (type) => setState(() {
                  _historyType = type;
                  _periodPage = 0;
                }),
              ),
            GoalDateFilter(
              dates: _historyDates,
              emptyLabel: 'Custom range',
              onChanged: (dates) => setState(() {
                _historyDates = dates;
                _periodPage = 0;
              }),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
      ],
      if (pageCount == 0)
        EmptyState.compact(
          icon: Icons.history,
          title: goalId == null && _historyType == null && dates == null
              ? 'No goal history yet'
              : 'No matching goal periods',
        ),
      if (visiblePeriods.isNotEmpty) _cards(context, visiblePeriods, historical: true),
      if (visibleArchived.isNotEmpty) ...[
        if (visiblePeriods.isNotEmpty) const SizedBox(height: Spacing.lg),
        Text('Archived goals', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Spacing.md),
        _cards(context, visibleArchived, historical: true, currentDetails: true),
      ],
      if (pageCount > 1) ...[
        const SizedBox(height: Spacing.md),
        ActivityPagination(
          page: page,
          pageCount: pageCount,
          previousLabel: 'Previous page',
          nextLabel: 'Next page',
          onChanged: (value) {
            setState(() => _periodPage = value);
            _historyScroll.jumpTo(0);
          },
        ),
      ],
    ];
  }

  Future<void> _goalAction(ReadingGoal goal, String action) async {
    if (action == 'edit') {
      await AddGoalSheet.show(context, provider: _provider, editing: _provider.store.getReadingGoal(goal.id));
      return;
    }

    final repository = _provider.store.trackingRepository;

    try {
      if (action == 'delete') {
        if (await confirmGoalDeletion(context) && mounted) {
          await _provider.deleteGoal(goal.id, repository: repository);
        }

        return;
      }

      if (action == 'pause') {
        await _provider.pauseGoal(goal.id, goal.isActive);
      }

      if (action == 'archive') {
        await _provider.archiveGoal(goal.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Goal archived'),
              action: SnackBarAction(label: 'Undo', onPressed: () => _restore(goal)),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _restore(ReadingGoal goal) => _provider.restoreGoal(goal.id);
}
