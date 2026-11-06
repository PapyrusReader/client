import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/providers/statistics_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/statistics/reading_charts.dart';
import 'package:papyrus/widgets/statistics/stat_card.dart';
import 'package:papyrus/widgets/statistics/statistics_row.dart';
import 'package:provider/provider.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.now});

  final DateTime Function()? now;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late final _provider = StatisticsProvider(now: widget.now);
  bool _showPages = false;

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
    final centered = context.select<PreferencesProvider, bool>((preferences) => preferences.pageAlignment == 'center');

    return ListenableBuilder(
      listenable: _provider,
      builder: (context, child) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= Breakpoints.desktopSmall;
              final padding = libraryPageHorizontalPadding(context);

              return RefreshIndicator(
                onRefresh: _provider.refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(padding),
                  child: Align(
                    alignment: centered ? Alignment.topCenter : Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: centered ? 1120 : double.infinity),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _periodControls(context),
                          const SizedBox(height: Spacing.lg),
                          if (_provider.isLoading) const AppLinearProgressIndicator(),
                          if (_provider.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Spacing.md),
                              child: Text(
                                _provider.error!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          _overview(context),
                          const SizedBox(height: Spacing.xl),
                          _columns(context, _activity(context, wide), _sessions(context)),
                          const SizedBox(height: Spacing.xl),
                          _columns(context, _consistency(context), _genres(context)),
                          if (_provider.selectedPeriod == StatsPeriod.year ||
                              _provider.selectedPeriod == StatsPeriod.allTime) ...[
                            const SizedBox(height: Spacing.xl),
                            StatSectionCard(
                              title: 'Books finished by month',
                              subtitle: _periodTitle,
                              child: _provider.monthlyStats.every((month) => month.booksRead == 0)
                                  ? const EmptyState.compact(
                                      icon: Icons.auto_stories_outlined,
                                      title: 'No books finished in this range',
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: (_provider.monthlyStats.length * 64.0).clamp(280, 100000),
                                        child: BooksPerMonthChart(
                                          monthlyStats: _provider.monthlyStats,
                                          isDesktop: wide,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _periodControls(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < Breakpoints.tablet;
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final period in StatsPeriod.values.where((period) => period != StatsPeriod.custom))
            Semantics(
              selected: _provider.selectedPeriod == period,
              child: TextButton(
                key: ValueKey('statistics-period-${period.name}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.symmetric(horizontal: compact ? Spacing.sm : Spacing.md),
                  textStyle: Theme.of(context).textTheme.labelLarge,
                  foregroundColor: _provider.selectedPeriod == period
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.primary,
                  backgroundColor: _provider.selectedPeriod == period
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.transparent,
                ),
                onPressed: () => _provider.setPeriod(period),
                child: Text(_periodLabel(period)),
              ),
            ),
        ],
      );

      return Row(
        children: [
          Expanded(
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: controls),
          ),
          const SizedBox(width: Spacing.sm),
          Semantics(
            selected: _provider.hasCustomRange,
            child: compact
                ? IconButton.outlined(
                    onPressed: _pickDates,
                    tooltip: 'Custom range',
                    isSelected: _provider.hasCustomRange,
                    icon: const Icon(Icons.date_range_outlined),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _pickDates,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: const Text('Custom range'),
                  ),
          ),
        ],
      );
    },
  );

  Widget _overview(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_periodTitle, style: textTheme.headlineSmall),
        const SizedBox(height: Spacing.sm),
        Text('Your reading at a glance', style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: Spacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final minimumWidth = MediaQuery.textScalerOf(context).scale(140);
            final columns = (constraints.maxWidth / minimumWidth).floor().clamp(1, 4);
            final width = (constraints.maxWidth - Spacing.md * (columns - 1)) / columns;

            return Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.lg,
              children: [
                for (final metric in [
                  (_provider.totalReadingLabel, 'Reading time'),
                  ('${_provider.pagesRead}', _provider.hasEstimatedPages ? 'Pages read (estimated)' : 'Pages read'),
                  ('${_provider.totalBooks}', 'Books finished'),
                  ('${_provider.daysRead}', 'Days read'),
                ])
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$1,
                          style: textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        const SizedBox(height: Spacing.xs),
                        if (metric.$2 == 'Days read')
                          Tooltip(
                            message: 'Days with at least 5 minutes of reading',
                            child: Text(
                              metric.$2,
                              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          )
                        else
                          Text(metric.$2, style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _columns(BuildContext context, Widget main, Widget aside) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 800 || MediaQuery.textScalerOf(context).scale(16) > 24) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            main,
            const SizedBox(height: Spacing.lg),
            aside,
          ],
        );
      }

      return StatisticsRow(main: main, aside: aside);
    },
  );

  String get _chartRange {
    final activities = _provider.readingTimeData;

    if (activities.isEmpty) {
      return _provider.periodLabel;
    }

    final dates =
        '${DateFormat.yMMMd().format(activities.first.date)} – '
        '${DateFormat.yMMMd().format(activities.last.endDate.subtract(const Duration(microseconds: 1)))}';
    if (activities.length == 1 && _provider.bucketSize == StatisticsBucketSize.day) {
      return DateFormat.yMMMd().format(activities.first.date);
    }

    return dates;
  }

  Widget _activity(BuildContext context, bool wide) {
    final activities = _provider.readingTimeData;
    final hasData = activities.any((activity) => _showPages ? activity.pages > 0 : activity.seconds > 0);

    return StatSectionCard(
      title: 'Reading activity',
      subtitle: _chartRange,
      action: Wrap(
        spacing: Spacing.xs,
        alignment: WrapAlignment.end,
        children: [
          ChoiceChip(
            label: const Text('Time'),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            labelPadding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            showCheckmark: false,
            selected: !_showPages,
            onSelected: (_) => setState(() => _showPages = false),
          ),
          ChoiceChip(
            label: const Text('Pages'),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            labelPadding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            showCheckmark: false,
            selected: _showPages,
            onSelected: (_) => setState(() => _showPages = true),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasData)
            EmptyState.compact(
              icon: Icons.auto_stories_outlined,
              title: _showPages ? 'No pages recorded in this range' : 'No reading time in this range',
            )
          else
            ReadingActivityBarChart(
              activities: activities,
              metric: _showPages ? ReadingActivityMetric.pages : ReadingActivityMetric.time,
              isDesktop: wide,
            ),
        ],
      ),
    );
  }

  Widget _sessions(BuildContext context) {
    final sessions = _provider.sessionStats;

    return StatSectionCard(
      title: 'Your reading rhythm',
      subtitle: _periodTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detail(context, 'Sessions', '${sessions.totalSessions}'),
          _detail(context, 'Average session', sessions.totalSessions == 0 ? '—' : sessions.averageSessionLabel),
          _detail(context, 'Books read', '${_provider.booksRead}'),
          Tooltip(
            message: 'Reading time per elapsed calendar day in the selected period, including days without reading',
            child: _detail(context, 'Daily average', _provider.averageReadingLabel),
          ),
        ],
      ),
    );
  }

  Widget _consistency(BuildContext context) {
    final streak = _provider.streak;
    String days(int count) => '$count ${count == 1 ? 'day' : 'days'}';

    return StatSectionCard(
      title: 'Reading consistency',
      subtitle: 'Lifetime streaks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detail(context, 'Current streak', days(streak.currentStreak)),
          _detail(context, 'Best streak', days(streak.bestStreak)),
        ],
      ),
    );
  }

  Widget _genres(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final genres = [..._provider.genreDistribution]..sort((left, right) => right.bookCount.compareTo(left.bookCount));

    return StatSectionCard(
      title: 'Reading by genre',
      subtitle: switch (_provider.selectedPeriod) {
        StatsPeriod.week => 'Books read this week',
        StatsPeriod.month => 'Books read this month',
        StatsPeriod.year => 'Books read this year',
        StatsPeriod.allTime => 'All books read',
        StatsPeriod.custom => 'Books read in this range',
      },
      child: genres.isEmpty
          ? const EmptyState.compact(
              icon: Icons.category_outlined,
              title: 'No genre data in this range',
            )
          : Column(
              children: [
                for (final genre in genres)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Semantics(
                      label: '${genre.genre}, ${genre.bookCount} books, ${(genre.percentage * 100).round()} percent',
                      child: ExcludeSemantics(
                        child: Column(
                          children: [
                            _detail(context, genre.genre, '${(genre.percentage * 100).round()}%'),
                            AppLinearProgressIndicator(
                              value: genre.percentage.clamp(0, 1),
                              minHeight: 4,
                              color: colors.primary,
                              backgroundColor: colors.surfaceContainerHighest,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final textTheme = Theme.of(context).textTheme;
        final labelWidget = Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
        final valueWidget = Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );

        if (constraints.maxWidth < MediaQuery.textScalerOf(context).scale(240)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: Spacing.xs),
              valueWidget,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Align(alignment: AlignmentDirectional.centerEnd, child: valueWidget),
            ),
          ],
        );
      },
    ),
  );

  String get _periodTitle => _provider.hasCustomRange ? 'Custom range' : _provider.periodLabel;

  String _periodLabel(StatsPeriod period) => switch (period) {
    StatsPeriod.week => 'Week',
    StatsPeriod.month => 'Month',
    StatsPeriod.year => 'Year',
    StatsPeriod.allTime => 'All time',
    StatsPeriod.custom => 'Custom range',
  };

  Future<void> _pickDates() async {
    final now = DateTime.now();

    final picked = await showAppDateRangePicker(
      context: context,
      useRootNavigator: false,
      initialDateRange: DateTimeRange(
        start: _provider.customStartDate ?? now.subtract(const Duration(days: 30)),
        end: _provider.customEndDate ?? now,
      ),
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Select date range',
      confirmText: 'Apply',
      saveText: 'Apply',
    );

    if (picked != null && mounted) {
      _provider.setCustomDateRange(picked.start, picked.end);
    }
  }
}
