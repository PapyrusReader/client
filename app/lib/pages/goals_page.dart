import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/goals/reading_activity_heatmap.dart';
import 'package:papyrus/widgets/goals/reading_activity_timeline.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> with SingleTickerProviderStateMixin {
  final _provider = GoalsProvider();
  bool _activity = false;
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, animationDuration: Duration.zero);
    _tabs.addListener(() {
      if (_activity != (_tabs.index == 1)) setState(() => _activity = _tabs.index == 1);
    });
  }

  String? _filterGoal;
  DateTimeRange? _filterDates;
  int? _activityYear;
  String _activityKind = 'all';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider.attach(context.read<DataStore>());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _provider,
    builder: (context, _) => GoalControls(
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth < Breakpoints.tablet ? Spacing.md : Spacing.xl;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: ListView(
                    padding: EdgeInsets.all(padding),
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final actions = Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, ComponentSizes.buttonHeightMobile),
                                ),
                                onPressed: () => LogReadingSheet.show(context, provider: _provider),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Log reading'),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, ComponentSizes.buttonHeightMobile),
                                ),
                                onPressed: () => AddGoalSheet.show(context, provider: _provider),
                                icon: const Icon(Icons.add),
                                label: const Text('New goal'),
                              ),
                            ],
                          );
                          if (box.maxWidth < 520 || MediaQuery.textScalerOf(context).scale(16) > 24) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Goals', style: Theme.of(context).textTheme.headlineMedium),
                                const SizedBox(height: Spacing.md),
                                actions,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: Text('Goals', style: Theme.of(context).textTheme.headlineMedium)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  actions.children.first,
                                  const SizedBox(width: Spacing.sm),
                                  actions.children.last,
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: Spacing.lg),
                      Align(alignment: AlignmentDirectional.centerStart, child: _viewTabs(context)),
                      const SizedBox(height: Spacing.xl),
                      if (_provider.isLoading)
                        const Center(child: AppCircularProgressIndicator())
                      else if (_activity)
                        ..._activityContent(context)
                      else
                        ..._overview(context),
                      if (_provider.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.md),
                          child: Text(_provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _viewTabs(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(16) <= 24) {
      return TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 1,
        labelPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
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
    final today = current
        .where((value) => value.goal.period == GoalPeriod.daily || value.goal.type == GoalType.days)
        .toList();
    final longer = current.where((value) => !today.contains(value)).toList();

    final texts = Theme.of(context).textTheme;
    return [
      if (current.isEmpty) ...[
        const EmptyState.compact(
          icon: Icons.flag_outlined,
          title: 'No goals yet',
          subtitle:
              'Choose a target that fits your reading. The reader tracks progress, and you can log physical books too.',
          alignment: Alignment.topCenter,
        ),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (var i = 0; i < 5; i++)
              ActionChip(
                label: Text(
                  [
                    '30 minutes daily',
                    '5 reading days weekly',
                    '12 books yearly',
                    '100 pages weekly',
                    'Finish a book',
                  ][i],
                ),
                onPressed: () => AddGoalSheet.show(context, provider: _provider, preset: i),
              ),
          ],
        ),
      ],
      if (today.isNotEmpty) ...[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.md,
          children: [
            Text('Today', style: texts.titleLarge),
            Text(
              DateFormat.MMMMEEEEd().format(DateTime.now()),
              style: texts.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _cards(context, today),
        const SizedBox(height: Spacing.xl),
      ],
      if (longer.isNotEmpty) ...[
        Text('Longer-term goals', style: texts.titleLarge),
        const SizedBox(height: Spacing.md),
        _cards(context, longer),
        const SizedBox(height: Spacing.xl),
      ],
      if (_provider.store.effectiveReadingActivities.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _tabs.index = 1,
            icon: const Icon(Icons.history),
            label: const Text('View activity'),
          ),
        ),
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
        bookProgressLabel: progress.goal.scope == GoalScope.book && progress.goal.type == GoalType.books && !historical
            ? '${((_provider.store.getBook(progress.goal.scopeId!)?.currentPosition ?? 0) * 100).round()}% through the book · Finish confirmation required'
            : null,
        onTap: () => GoalDetailsSheet.show(
          context,
          goal: progress.goal,
          provider: _provider,
          historical: historical ? progress : null,
        ),
        onContinue: historical ? null : () => _continueReading(progress.goal),
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
    GoalScope.book => _provider.store.getBook(goal.scopeId!)?.title ?? 'Removed book',
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
          key: const Key('goal-period-history'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Goal history'),
          subtitle: const Text('Past periods and archived goals'),
          children: [
            if (filtered.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _cards(context, filtered, historical: true),
            ],
            if (archived.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('Archived goals', style: Theme.of(context).textTheme.titleMedium),
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
    if (action == 'delete') {
      await GoalDetailsSheet.show(context, goal: goal, provider: _provider);
      return;
    }
    try {
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
  Future<void> _continueReading(ReadingGoal goal) async {
    final candidates =
        _provider.store.books
            .where(
              (book) =>
                  goal.scope == GoalScope.library ||
                  goal.scope == GoalScope.book && book.id == goal.scopeId ||
                  goal.scope == GoalScope.shelf && _provider.store.getShelfIdsForBook(book.id).contains(goal.scopeId),
            )
            .toList()
          ..sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
    if (candidates.isEmpty) {
      await LogReadingSheet.show(context, provider: _provider);
      return;
    }
    Book? selected;
    final readable = candidates
        .where(
          (book) =>
              !book.isPhysical &&
              ReaderBookAdapter.formatFor(book.fileFormat) != null &&
              book.readingStatus == LibraryReadingStatus.inProgress,
        )
        .toList();
    if (readable.isNotEmpty) {
      selected = readable.first;
    } else if (goal.scope == GoalScope.book) {
      selected = candidates.first;
    } else {
      selected = await showModalBottomSheet<Book>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        sheetAnimationStyle: AppMotion.animationStyle(context),
        builder: (context) => AppBottomSheet(
          title: 'Choose a book',
          onClose: () => Navigator.pop(context),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final book in candidates)
                ListTile(
                  title: Text(book.title),
                  subtitle: Text(book.isPhysical ? 'Log physical-book reading' : book.author),
                  onTap: () => Navigator.pop(context, book),
                ),
            ],
          ),
        ),
      );
    }
    if (selected == null || !mounted) return;
    var available = selected.fileMediaId != null;
    try {
      available |= await context.read<BookImportService>().hasBookFile(selected.id);
    } catch (_) {}
    if (!mounted) return;
    if (selected.isPhysical || ReaderBookAdapter.formatFor(selected.fileFormat) == null || !available) {
      await LogReadingSheet.show(context, provider: _provider, book: selected);
      return;
    }
    context.goNamed('BOOK_READER', pathParameters: {'bookId': selected.id});
  }
}
