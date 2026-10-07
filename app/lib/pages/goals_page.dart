import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/goals/reading_activity_heatmap.dart';
import 'package:papyrus/widgets/goals/reading_activity_timeline.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> with TickerProviderStateMixin {
  final _provider = GoalsProvider();
  bool _activity = false;
  bool _hideCompleted = false;
  late TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_activity != (_tabs.index == 1)) setState(() => _activity = _tabs.index == 1);
  }

  String? _filterGoal;
  DateTimeRange? _filterDates;
  int? _activityYear;
  String _activityKind = 'all';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = AppMotion.duration(context, kTabScrollDuration);
    if (_tabs.animationDuration != duration) {
      final index = _tabs.index;
      _tabs.removeListener(_onTabChanged);
      _tabs.dispose();
      _tabs = TabController(length: 2, vsync: this, initialIndex: index, animationDuration: duration);
      _tabs.addListener(_onTabChanged);
    }
    _provider.attach(context.read<DataStore>());
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _provider,
    builder: (context, _) => GoalControls(
      child: Scaffold(
        floatingActionButton: _usesFab(context)
            ? FloatingActionButton(
                tooltip: 'New goal',
                onPressed: () => AddGoalSheet.show(context, provider: _provider),
                child: const Icon(Icons.add),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = libraryPageHorizontalPadding(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(padding: EdgeInsets.fromLTRB(padding, padding, padding, 0), child: _viewTabs(context)),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _tabContent(context, padding, activity: false),
                        _tabContent(context, padding, activity: true),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _tabContent(BuildContext context, double padding, {required bool activity}) {
    if (!activity && !_provider.isLoading && _provider.error == null) {
      if (_provider.current.isEmpty) {
        return EmptyState(
          key: const Key('goals-empty-state'),
          icon: Icons.emoji_events_outlined,
          title: 'No goals yet',
          subtitle: 'Create a goal to track your reading progress.',
          action: EmptyStateAction(
            label: 'New goal',
            icon: Icons.add,
            onPressed: () => AddGoalSheet.show(context, provider: _provider),
          ),
        );
      }
      if (_hideCompleted && _provider.current.every((progress) => progress.reached)) {
        return const EmptyState.compact(icon: Icons.check_circle_outline, title: 'All goals completed');
      }
    }
    return ListView(
      key: PageStorageKey(activity ? 'goals-activity-scroll' : 'goals-overview-scroll'),
      padding: EdgeInsets.fromLTRB(
        padding,
        Spacing.lg,
        padding,
        // Let the final row scroll clear of the creation FAB.
        padding + (_usesFab(context) ? kToolbarHeight + Spacing.lg : 0),
      ),
      children: [
        if (_provider.isLoading)
          const Center(child: AppCircularProgressIndicator())
        else if (activity)
          ..._activityContent(context)
        else
          ..._overview(context),
        if (_provider.error != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: Text(_provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  bool _usesFab(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

  Widget _pageActions(BuildContext context, {required bool compact}) => Wrap(
    spacing: Spacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
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
      if (!_usesFab(context))
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
  );

  Widget _viewTabs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tabControl(context)),
            if (!_activity && _provider.current.isNotEmpty)
              Semantics(
                value: _hideCompleted ? 'Completed goals hidden' : 'Showing completed goals',
                child: PopupMenuButton<bool>(
                  tooltip: 'Goal filters',
                  icon: Badge(
                    isLabelVisible: _hideCompleted,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.filter_list),
                  ),
                  onSelected: (value) => setState(() => _hideCompleted = value),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem<bool>(
                      value: !_hideCompleted,
                      checked: _hideCompleted,
                      child: const Text('Hide completed'),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: Spacing.sm),
            // Desktop controls use the same 40px target as collection actions.
            // Top-align their painted bounds in the standard 48px tab row.
            Theme(
              data: Theme.of(context).copyWith(
                materialTapTargetSize: _usesFab(context)
                    ? Theme.of(context).materialTapTargetSize
                    : MaterialTapTargetSize.shrinkWrap,
              ),
              child: _pageActions(
                context,
                compact:
                    _usesFab(context) || constraints.maxWidth < 640 || MediaQuery.textScalerOf(context).scale(1) > 1.4,
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  );

  Widget _tabControl(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(16) <= 24) {
      return TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        dividerColor: Theme.of(context).colorScheme.outlineVariant,
        labelPadding: EdgeInsets.symmetric(horizontal: _usesFab(context) ? Spacing.sm : Spacing.md),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Activity'),
        ],
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Spacing.sm,
      children: [
        for (var index = 0; index < 2; index++)
          Semantics(
            selected: _tabs.index == index,
            child: TextButton(
              onPressed: () => _tabs.index = index,
              style: TextButton.styleFrom(foregroundColor: _tabs.index == index ? colors.primary : colors.onSurface),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _tabs.index == index ? colors.primary : Colors.transparent, width: 2),
                  ),
                ),
                child: Text(index == 0 ? 'Overview' : 'Activity'),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _overview(BuildContext context) {
    final current = _provider.current;
    // Recurrence describes a goal's schedule; activity determines its place here.
    final groups = <String, List<GoalProgress>>{'In progress': [], 'Not started': [], 'Completed': [], 'Paused': []};
    for (final progress in current) {
      if (_hideCompleted && progress.reached) continue;
      final status = !progress.projected.isActive
          ? 'Paused'
          : progress.reached
          ? 'Completed'
          : progress.fraction > 0
          ? 'In progress'
          : 'Not started';
      groups[status]!.add(progress);
    }
    for (final goals in groups.values) {
      goals.sort((a, b) {
        final progress = b.fraction.compareTo(a.fraction);
        if (progress != 0) return progress;
        final deadline = a.range.end.compareTo(b.range.end);
        if (deadline != 0) return deadline;
        final created = a.goal.createdAt.compareTo(b.goal.createdAt);
        return created != 0 ? created : a.goal.id.compareTo(b.goal.id);
      });
    }

    final texts = Theme.of(context).textTheme;
    return [
      for (final group in groups.entries)
        if (group.value.isNotEmpty) ...[
          Text(group.key, style: texts.titleLarge),
          const SizedBox(height: Spacing.md),
          _cards(context, group.value),
          const SizedBox(height: Spacing.xl),
        ],
    ];
  }

  Widget _cards(BuildContext context, List<GoalProgress> goals, {bool historical = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 && MediaQuery.textScalerOf(context).scale(16) <= 24 ? 2 : 1;
      Widget card(GoalProgress progress) => GoalCard(
        key: ValueKey('goal-card-${progress.goal.id}${historical ? '-${progress.range.start.toIso8601String()}' : ''}'),
        fillHeight: columns == 2,
        goal: progress.goal,
        progress: progress,
        scopeLabel: _scopeLabel(progress.goal),
        onTap: () => GoalDetailsSheet.show(
          context,
          goal: progress.goal,
          provider: _provider,
          historical: historical ? progress : null,
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
  List<Widget> _activityContent(BuildContext context) {
    final periods = _provider.history;
    final names = <String, String>{
      for (final record in periods) record.goal.id: record.goal.displayTitle,
      for (final goal in _provider.store.goalDefinitions) goal.id: goal.displayTitle,
    };
    if (!names.containsKey(_filterGoal)) _filterGoal = null;
    final selected = _filterGoal == null
        ? null
        : _provider.store.getReadingGoal(_filterGoal!) ?? periods.where((p) => p.goal.id == _filterGoal).first.goal;
    final timezone = selected?.timezone ?? GoalCalendar.systemTimezone;
    final now = _provider.now;
    final year = _activityYear ?? GoalCalendar.local(now, timezone).year;
    final yearRange = GoalCalendar.calendarPeriod(GoalPeriod.yearly, DateTime.utc(year, 1, 2), timezone);
    final dateRange = _filterDates == null
        ? yearRange
        : GoalRange(
            GoalCalendar.dayOffset(GoalCalendar.deadline(_filterDates!.start, timezone), -1, timezone),
            GoalCalendar.deadline(_filterDates!.end, timezone),
          );
    final range = dateRange;
    final scoped = _provider.store.readingActivities
        .where((a) => selected == null || matchesGoal(selected, a))
        .toList();
    final corrected = _provider.store.readingActivities
        .where((a) => a.kind == 'reversal')
        .map((a) => a.correctionOf)
        .whereType<String>()
        .toSet();
    bool matchesKind(ReadingActivity a) => switch (_activityKind) {
      'reader' => a.source == 'reader',
      'manual' => a.source != 'reader',
      'finished' => a.kind == 'completion',
      'corrected' => corrected.contains(a.id),
      _ => true,
    };
    // Apply reversals before source filters: a manual correction can undo reader activity.
    final effective = effectiveActivities(scoped).where((a) => _activityKind != 'corrected' && matchesKind(a)).toList();
    final visible =
        (_activityKind == 'corrected' ? scoped.where((a) => a.kind != 'reversal' && matchesKind(a)) : effective)
            .where(
              (a) => (a.kind == 'reading' && a.endTime.isAfter(a.startTime)
                  ? a.endTime.isAfter(range.start) && a.startTime.isBefore(range.end)
                  : range.contains(a.endTime)),
            )
            .toList();
    final totals = projectGoal(
      ReadingGoal(
        id: 'activity-summary',
        type: GoalType.minutes,
        targetValue: 1,
        period: GoalPeriod.custom,
        createdAt: range.start,
        startDate: range.start,
        endDate: range.end,
        timezone: timezone,
        isRecurring: false,
      ),
      effective,
      now,
      period: range,
    );
    final filtered = periods
        .where(
          (p) =>
              (_filterGoal == null || p.goal.id == _filterGoal) &&
              p.range.start.isBefore(range.end) &&
              p.range.end.isAfter(range.start),
        )
        .toList();
    final archived = _provider.store.goalDefinitions
        .where((goal) => goal.isArchived && (_filterGoal == null || _filterGoal == goal.id))
        .map(_provider.progress)
        .toList();
    return [
      ReadingActivityHeatmap(
        activities: effective,
        year: year,
        timezone: timezone,
        now: now,
        selectedDay: _filterDates?.start == _filterDates?.end && _filterDates != null
            ? GoalCalendar.dayOffset(GoalCalendar.deadline(_filterDates!.start, timezone), -1, timezone)
            : null,
        onYearChanged: (value) => setState(() {
          _activityYear = value;
          _filterDates = null;
        }),
        onDaySelected: (day) => setState(() {
          final local = GoalCalendar.local(day, timezone);
          final civil = DateTime(local.year, local.month, local.day);
          _filterDates = DateTimeRange(start: civil, end: civil);
        }),
      ),
      const SizedBox(height: Spacing.lg),
      Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - Spacing.xl * 2).clamp(120, 220).toDouble(),
            child: DropdownButtonFormField<String>(
              initialValue: _activityKind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: [
                for (final value in {
                  'all': 'All activity',
                  'reader': 'Reader',
                  'manual': 'Manual',
                  'finished': 'Finished books',
                  'corrected': 'Corrected entries',
                }.entries)
                  DropdownMenuItem(value: value.key, child: Text(value.value)),
              ],
              onChanged: (value) => setState(() => _activityKind = value!),
            ),
          ),
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - Spacing.xl * 2).clamp(120, 280).toDouble(),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_filterGoal),
              initialValue: _filterGoal ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Goal scope'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Whole library')),
                for (final name in names.entries)
                  DropdownMenuItem(
                    value: name.key,
                    child: Text(name.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _filterGoal = value == '' ? null : value),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final dates = await showAppDateRangePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                initialDateRange: _filterDates,
              );
              if (dates != null && mounted) {
                setState(() {
                  _filterDates = dates;
                  _activityYear = dates.end.year;
                });
              }
            },
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              _filterDates == null
                  ? 'Filter dates'
                  : _filterDates!.start == _filterDates!.end
                  ? DateFormat.MMMd().format(_filterDates!.start)
                  : '${DateFormat.MMMd().format(_filterDates!.start)} – ${DateFormat.MMMd().format(_filterDates!.end)}',
            ),
          ),
          if (_filterDates != null)
            TextButton(onPressed: () => setState(() => _filterDates = null), child: const Text('Clear dates')),
        ],
      ),
      const SizedBox(height: Spacing.lg),
      if (_activityKind != 'corrected')
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.md,
            children: [
              _activityTotal(context, '${totals.finishedBooks}', 'books finished'),
              _activityTotal(
                context,
                '${totals.pages.floor()}',
                totals.estimated ? 'pages (includes estimates)' : 'pages read',
              ),
              _activityTotal(
                context,
                totals.seconds < 60 ? '${totals.seconds} sec' : formatDuration(totals.seconds ~/ 60),
                'reading time',
              ),
            ],
          ),
        ),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: Spacing.lg),
          child: EmptyState.compact(
            icon: Icons.history_outlined,
            title: 'No reading activity',
            subtitle: 'Reading and manual logs will appear here.',
            alignment: Alignment.topCenter,
          ),
        )
      else
        ReadingActivityTimeline(
          activities: visible,
          provider: _provider,
          timezone: timezone,
          correctedIds: corrected,
          range: range,
        ),
      const SizedBox(height: Spacing.lg),
      if (filtered.isNotEmpty || archived.isNotEmpty)
        ExpansionTile(
          key: const PageStorageKey('goal-period-history'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: Spacing.xs),
          shape: const Border(),
          collapsedShape: const Border(),
          textColor: Theme.of(context).colorScheme.onSurface,
          collapsedTextColor: Theme.of(context).colorScheme.onSurface,
          title: Text('Goal history', style: Theme.of(context).textTheme.titleLarge),
          children: [
            if (filtered.isNotEmpty) _cards(context, filtered, historical: true),
            if (archived.isNotEmpty) ...[
              if (filtered.isNotEmpty) const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Archived goals',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: Spacing.md),
              _cards(context, archived, historical: true),
            ],
          ],
        ),
    ];
  }

  Widget _activityTotal(BuildContext context, String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

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
      if (action == 'pause') await _provider.pauseGoal(goal.id, goal.isActive);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _restore(ReadingGoal goal) => _provider.restoreGoal(goal.id);
}
