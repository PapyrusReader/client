import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/goals/goal_progress.dart';
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
import 'package:papyrus/widgets/goals/goal_details_sheet.dart';
import 'package:papyrus/widgets/goals/log_reading_sheet.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _provider = GoalsProvider();
  bool _history = false;
  String? _filterGoal;
  DateTimeRange? _filterDates;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider.attach(context.read<DataStore>());
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _provider,
    builder: (context, _) => Scaffold(
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Overview')),
                          ButtonSegment(value: true, label: Text('History')),
                        ],
                        selected: {_history},
                        onSelectionChanged: (selection) => setState(() => _history = selection.first),
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    if (_provider.isLoading)
                      const Center(child: AppCircularProgressIndicator())
                    else if (_history)
                      ..._historyContent(context)
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
  );

  List<Widget> _overview(BuildContext context) {
    final current = _provider.current;
    final today = current
        .where((value) => value.goal.period == GoalPeriod.daily || value.goal.type == GoalType.days)
        .toList();
    final longer = current.where((value) => !today.contains(value)).toList();
    final activity = groupReadingActivities(_provider.store.effectiveReadingActivities);
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
        Text('Today · ${DateFormat.MMMMEEEEd().format(DateTime.now())}', style: texts.titleLarge),
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
      if (activity.isNotEmpty) ...[
        Text('Recent activity', style: texts.titleLarge),
        const SizedBox(height: Spacing.sm),
        for (final entry in activity.take(5)) ReadingActivityTile(activity: entry, provider: _provider),
        TextButton(onPressed: () => setState(() => _history = true), child: const Text('View history')),
      ],
    ];
  }

  Widget _cards(BuildContext context, List<GoalProgress> goals, {bool historical = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 && MediaQuery.textScalerOf(context).scale(16) <= 24 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * Spacing.md) / columns;
      return Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        children: [
          for (final progress in goals)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GoalCard(
                    goal: progress.goal,
                    progress: progress,
                    scopeLabel: _scopeLabel(progress.goal),
                    onTap: () => GoalDetailsSheet.show(
                      context,
                      goal: progress.goal,
                      provider: _provider,
                      historical: historical ? progress : null,
                    ),
                    onContinue: historical ? null : () => _continueReading(progress.goal),
                    onMenu: historical ? null : (action) => _goalAction(progress.goal, action),
                  ),
                  if (progress.goal.scope == GoalScope.book && progress.goal.type == GoalType.books && !historical)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm, left: Spacing.lg),
                      child: Text(
                        '${((_provider.store.getBook(progress.goal.scopeId!)?.currentPosition ?? 0) * 100).round()}% through the book · Finish confirmation required',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
  String _scopeLabel(ReadingGoal goal) => switch (goal.scope) {
    GoalScope.library => 'Whole library',
    GoalScope.book => _provider.store.getBook(goal.scopeId!)?.title ?? 'Removed book',
    GoalScope.shelf => _provider.store.getShelf(goal.scopeId!)?.name ?? 'Removed shelf',
  };
  List<Widget> _historyContent(BuildContext context) {
    final periods = _provider.history;
    final names = <String, String>{
      for (final record in periods) record.goal.id: record.goal.displayTitle,
      for (final goal in _provider.store.goalDefinitions) goal.id: goal.displayTitle,
    };
    if (!names.containsKey(_filterGoal)) _filterGoal = null;
    final selectedDefinition = _filterGoal == null
        ? null
        : _provider.store.getReadingGoal(_filterGoal!) ?? periods.where((p) => p.goal.id == _filterGoal).first.goal;
    final activity =
        _provider.store.readingActivities
            .where(
              (a) =>
                  a.kind != 'reversal' &&
                  (selectedDefinition == null || matchesGoal(selectedDefinition, a)) &&
                  (_filterDates == null ||
                      !a.endTime.isBefore(_filterDates!.start) &&
                          a.endTime.isBefore(_filterDates!.end.copyWith(day: _filterDates!.end.day + 1))),
            )
            .toList()
          ..sort((a, b) => b.endTime.compareTo(a.endTime));
    final corrected = _provider.store.readingActivities
        .where((a) => a.kind == 'reversal')
        .map((a) => a.correctionOf)
        .toSet();
    final filtered = periods
        .where(
          (p) =>
              (_filterGoal == null || p.goal.id == _filterGoal) &&
              (_filterDates == null ||
                  p.range.start.isBefore(_filterDates!.end.copyWith(day: _filterDates!.end.day + 1)) &&
                      p.range.end.isAfter(_filterDates!.start)),
        )
        .toList();
    final archived = _provider.store.goalDefinitions
        .where((goal) => goal.isArchived && (_filterGoal == null || _filterGoal == goal.id))
        .map(_provider.progress)
        .toList();
    return [
      Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - Spacing.xl * 2).clamp(120, 300).toDouble(),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_filterGoal),
              initialValue: _filterGoal ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Goal'),
              items: [
                const DropdownMenuItem(value: '', child: Text('All goals')),
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
              if (dates != null && mounted) setState(() => _filterDates = dates);
            },
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              _filterDates == null
                  ? 'Filter dates'
                  : '${DateFormat.MMMd().format(_filterDates!.start)} – ${DateFormat.MMMd().format(_filterDates!.end)}',
            ),
          ),
          if (_filterDates != null)
            TextButton(onPressed: () => setState(() => _filterDates = null), child: const Text('Clear dates')),
        ],
      ),
      const SizedBox(height: Spacing.xl),
      if (filtered.isNotEmpty) ...[
        Text('Previous periods', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Spacing.md),
        _cards(context, filtered, historical: true),
        const SizedBox(height: Spacing.xl),
      ],
      if (archived.isNotEmpty) ...[
        Text('Archived goals', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Spacing.md),
        _cards(context, archived, historical: true),
        const SizedBox(height: Spacing.xl),
      ],
      Text('Reading activity', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: Spacing.sm),
      if (activity.isEmpty)
        const EmptyState.compact(
          icon: Icons.history_outlined,
          title: 'No reading activity',
          subtitle: 'Reading and manual logs will appear here.',
          alignment: Alignment.topCenter,
        )
      else
        for (final entry in [
          ...groupReadingActivities(activity.where((entry) => !corrected.contains(entry.id))),
          ...groupReadingActivities(activity.where((entry) => corrected.contains(entry.id))),
        ])
          ReadingActivityTile(activity: entry, provider: _provider, corrected: corrected.contains(entry.id)),
    ];
  }

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
