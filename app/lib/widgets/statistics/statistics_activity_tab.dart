import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/goal_history_filters.dart';
import 'package:papyrus/widgets/goals/reading_activity_heatmap.dart';
import 'package:papyrus/widgets/goals/reading_activity_timeline.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:provider/provider.dart';

class StatisticsActivityTab extends StatefulWidget {
  const StatisticsActivityTab({super.key, this.now});
  final DateTime Function()? now;

  @override
  State<StatisticsActivityTab> createState() => _StatisticsActivityTabState();
}

class _StatisticsActivityTabState extends State<StatisticsActivityTab> with AutomaticKeepAliveClientMixin {
  late final _provider = GoalsProvider(now: widget.now);
  String? _filterGoal;
  DateTimeRange? _filterDates;
  int? _activityYear;
  String _activityKind = 'all';
  bool _showFilters = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider.attach(context.watch<DataStore>());
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final padding = libraryPageHorizontalPadding(context);

    return GoalControls(
      child: ListenableBuilder(
        listenable: _provider,
        builder: (context, _) {
          if (_provider.isLoading) {
            return const Center(child: AppCircularProgressIndicator());
          }

          if (!_provider.store.isLoaded && _provider.error != null) {
            return const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Waiting for your library',
              subtitle: 'Your activity will appear when the connection is restored.',
            );
          }

          return ListView(
            key: const PageStorageKey('statistics-activity-scroll'),
            padding: EdgeInsets.all(padding),
            children: [
              ..._activityContent(context),
              if (_provider.error != null)
                Text(_provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _activityContent(BuildContext context) {
    final definitions = _provider.historyDefinitions;
    final selected = definitions[_filterGoal];
    final timezone = selected?.timezone ?? GoalCalendar.systemTimezone;
    final now = _provider.now;
    final year = _activityYear ?? GoalCalendar.local(now, timezone).year;
    final yearRange = GoalCalendar.calendarPeriod(GoalPeriod.yearly, DateTime.utc(year, 1, 2), timezone);

    final range = goalDateRange(_filterDates, timezone) ?? yearRange;
    final ledger = _provider.store.readingActivities;
    final scoped = ledger.where((activity) => selected == null || matchesGoal(selected, activity)).toList();

    final corrected = ledger
        .where((activity) => activity.kind == 'reversal')
        .map((activity) => activity.correctionOf)
        .whereType<String>()
        .toSet();

    bool matchesKind(ReadingActivity activity) => switch (_activityKind) {
      'reader' => activity.source == 'reader',
      'manual' => activity.source != 'reader',
      'finished' => activity.kind == 'completion',
      _ => true,
    };

    // Resolve reversals before filtering by source, since a manual correction can undo reader activity.
    final filtered = _activityKind == 'corrected'
        ? scoped.where((activity) => corrected.contains(activity.id) && activity.kind != 'reversal').toList()
        : effectiveActivities(scoped).where(matchesKind).toList();

    final visible = filtered.where((activity) {
      if (activity.kind == 'reading' && activity.endTime.isAfter(activity.startTime)) {
        return activity.endTime.isAfter(range.start) && activity.startTime.isBefore(range.end);
      }

      return range.contains(activity.endTime);
    }).toList();

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
      visible,
      now,
      period: range,
    );

    return [
      ReadingActivityHeatmap(
        activities: _activityKind == 'corrected' ? const [] : filtered,
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
      _filters(context, definitions, selected),
      const SizedBox(height: Spacing.lg),
      if (_activityKind != 'corrected')
        Container(
          padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.md,
            children: [
              _activityTotal(
                context,
                '${totals.finishedBooks}',
                totals.finishedBooks == 1 ? 'book finished' : 'books finished',
              ),
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
          key: ValueKey((selected?.id, _activityKind, range.start, range.end)),
          activities: visible,
          provider: _provider,
          timezone: timezone,
          correctedIds: corrected,
          range: range,
        ),
    ];
  }

  Widget _filters(BuildContext context, Map<String, ReadingGoal> definitions, ReadingGoal? selected) {
    final filters = <Widget>[
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
      GoalScopeFilter(
        definitions: definitions,
        selected: selected,
        onChanged: (id) => setState(() => _filterGoal = id),
      ),
      GoalDateFilter(
        dates: _filterDates,
        onChanged: (dates) => setState(() {
          _filterDates = dates;

          if (dates != null) {
            _activityYear = dates.end.year;
          }
        }),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < Breakpoints.tablet;
        final active = [selected != null, _activityKind != 'all', _filterDates != null].where((value) => value).length;

        return Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (compact)
              Semantics(
                expanded: _showFilters,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  icon: const Icon(Icons.filter_list),
                  label: Text(active == 0 ? 'Filters' : 'Filters ($active)'),
                ),
              ),
            if (!compact || _showFilters) ...filters,
          ],
        );
      },
    );
  }

  Widget _activityTotal(BuildContext context, String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
