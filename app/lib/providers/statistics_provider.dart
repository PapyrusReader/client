import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/daily_activity.dart';
import 'package:papyrus/models/genre_stats.dart';
import 'package:papyrus/models/reading_streak.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';

/// Time period for statistics filtering.
enum StatsPeriod { week, month, year, allTime, custom }

enum StatisticsBucketSize { day, month, year }

/// A chart interval with exact values and explicit calendar boundaries.
class StatisticsActivity extends DailyActivity {
  StatisticsActivity({
    required super.date,
    required this.endDate,
    required this.seconds,
    required this.pages,
    required this.bucketSize,
    required super.booksRead,
  }) : super(readingMinutes: seconds ~/ 60, pagesRead: pages.floor());

  final DateTime endDate;
  final int seconds;
  final double pages;
  final StatisticsBucketSize bucketSize;

  double get minutes => seconds / 60;

  String get intervalLabel => switch (bucketSize) {
    StatisticsBucketSize.day => DateFormat.yMMMd().format(date),
    StatisticsBucketSize.month => DateFormat.yMMM().format(date),
    StatisticsBucketSize.year => DateFormat.y().format(date),
  };

  String get axisLabel => switch (bucketSize) {
    StatisticsBucketSize.day => DateFormat.MMMd().format(date),
    StatisticsBucketSize.month => DateFormat('MMM yy').format(date),
    StatisticsBucketSize.year => DateFormat.y().format(date),
  };

  @override
  String get readingTimeLabel => seconds > 0 && seconds < 60 ? '${seconds}s' : super.readingTimeLabel;
}

/// Monthly reading statistics.
class MonthlyStats {
  final int month;
  final int year;
  final int booksRead;
  final int pagesRead;
  final int readingMinutes;

  const MonthlyStats({
    required this.month,
    required this.year,
    required this.booksRead,
    required this.pagesRead,
    required this.readingMinutes,
  });

  String get monthLabel {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String get fullMonthLabel {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }
}

/// Reading session statistics.
class SessionStats {
  final int totalSessions;
  final int totalMinutes;
  final int totalPages;
  final int totalSeconds;

  const SessionStats({
    required this.totalSessions,
    required this.totalMinutes,
    required this.totalPages,
    int? totalSeconds,
  }) : totalSeconds = totalSeconds ?? totalMinutes * 60;

  /// Average session duration in minutes.
  double get averageSessionDuration => totalSessions > 0 ? totalSeconds / 60 / totalSessions : 0;

  /// Reading velocity (pages per hour).
  double get pagesPerHour => totalMinutes > 0 ? (totalPages / totalMinutes) * 60 : 0;

  /// Formatted average session duration.
  String get averageSessionLabel {
    final seconds = (averageSessionDuration * 60).round();

    if (seconds > 0 && seconds < 60) {
      return '${seconds}s';
    }

    final avg = averageSessionDuration.round();

    if (avg < 60) {
      return '${avg}m';
    }

    final hours = avg ~/ 60;
    final minutes = avg % 60;

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }

  /// Formatted reading velocity.
  String get velocityLabel => '${pagesPerHour.toStringAsFixed(1)} pages/hr';
}

/// Provider for statistics page state management.
/// Uses DataStore as the single source of truth.
class StatisticsProvider extends ChangeNotifier {
  StatisticsProvider({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  GoalProgress? _periodTotals;
  DataStore? _dataStore;

  // Loading state
  bool _isLoading = false;
  String? _error;

  // Selected period
  StatsPeriod _selectedPeriod = StatsPeriod.week;

  // Custom date range
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Chart data
  List<StatisticsActivity> _readingTimeData = [];
  List<StatisticsActivity> _pagesReadData = [];
  List<MonthlyStats> _monthlyStats = [];
  List<GenreStats> _genreDistribution = [];
  ReadingStreak _streak = ReadingStreak.empty;

  /// Attach to a DataStore instance.
  void attach(DataStore dataStore) {
    if (_dataStore != dataStore) {
      _dataStore?.removeListener(_onDataStoreChanged);
      _dataStore = dataStore;
      _dataStore!.addListener(_onDataStoreChanged);
      _updateDataForPeriod();
      notifyListeners();
    }
  }

  void _onDataStoreChanged() {
    _updateDataForPeriod();
    notifyListeners();
  }

  @override
  void dispose() {
    _dataStore?.removeListener(_onDataStoreChanged);
    super.dispose();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  StatsPeriod get selectedPeriod => _selectedPeriod;
  DateTime? get customStartDate => _customStartDate;
  DateTime? get customEndDate => _customEndDate;

  /// Total books completed in the selected period.
  int get totalBooks {
    if (_dataStore == null) {
      return 0;
    }

    final range = _getDateRangeForPeriod();
    return _completedBooks(range.start, range.end).length;
  }

  Set<String> _completedBooks(DateTime start, DateTime end) {
    final store = _dataStore;

    if (store == null) {
      return {};
    }

    final trackedBooks = store.readingActivities
        .where((activity) => activity.kind == 'completion')
        .map((activity) => activity.bookId)
        .toSet();

    return {
      for (final activity in store.effectiveReadingActivities)
        if (activity.kind == 'completion' && !activity.endTime.isBefore(start) && activity.endTime.isBefore(end))
          activity.bookId,
      // Pre-ledger completion dates remain history without contributing to new goals.
      for (final book in store.books)
        if (!trackedBooks.contains(book.id) &&
            book.completedAt != null &&
            !book.completedAt!.isBefore(start) &&
            book.completedAt!.isBefore(end))
          book.id,
    };
  }

  /// Goals completed in the selected period.
  int get goalsCompleted {
    if (_dataStore == null) {
      return 0;
    }

    final range = _getDateRangeForPeriod();
    final now = _now().toUtc();
    final periods = <String, ReadingGoal>{};

    for (final record in _dataStore!.goalPeriods) {
      periods['${record.goalId}:${record.definition.startDate.microsecondsSinceEpoch}'] = record.definition;
    }

    for (final goal in _dataStore!.goalDefinitions) {
      for (final period in GoalCalendar.pastPeriods(goal, now)) {
        periods['${goal.id}:${period.start.microsecondsSinceEpoch}'] = goal.copyWith(
          startDate: period.start,
          endDate: period.end,
          isRecurring: false,
        );
      }
    }

    return periods.values
        .where(
          (goal) =>
              !goal.endDate.isBefore(range.start) &&
              goal.endDate.isBefore(range.end) &&
              projectGoal(goal, _dataStore!.readingActivities, now).reached,
        )
        .length;
  }

  int get totalReadingSeconds => _periodTotals?.seconds ?? 0;
  int get totalReadingMinutes => totalReadingSeconds ~/ 60;
  int get pagesRead => (_periodTotals?.pages ?? 0).floor();
  bool get hasEstimatedPages => _periodTotals?.estimated ?? false;

  /// Uses the same five-minute qualification as reading-day goals and streaks.
  int get daysRead => _periodTotals?.days ?? 0;

  Set<String> get _readBookIds {
    final range = _getDateRangeForPeriod();
    return {
      for (final activity in _periodTotals?.activities ?? <ReadingActivity>[])
        if (activity.kind == 'reading') activity.bookId,
      ..._completedBooks(range.start, range.end),
    };
  }

  int get booksRead => _readBookIds.length;

  int get periodDays {
    final range = _getDateRangeForPeriod();
    return DateTime.utc(
      range.end.year,
      range.end.month,
      range.end.day,
    ).difference(DateTime.utc(range.start.year, range.start.month, range.start.day)).inDays.clamp(1, 1000000);
  }

  String get activityIntervalLabel => switch (bucketSize) {
    StatisticsBucketSize.day => 'Daily totals',
    StatisticsBucketSize.month => 'Monthly totals',
    StatisticsBucketSize.year => 'Yearly totals',
  };

  StatisticsBucketSize get bucketSize {
    if (_selectedPeriod == StatsPeriod.year) {
      return StatisticsBucketSize.month;
    }

    if (periodDays <= 60) {
      return StatisticsBucketSize.day;
    }

    return periodDays <= 366 * 5 ? StatisticsBucketSize.month : StatisticsBucketSize.year;
  }

  /// Session statistics for the selected period.
  SessionStats get sessionStats {
    if (_dataStore == null) {
      return const SessionStats(totalSessions: 0, totalMinutes: 0, totalPages: 0);
    }

    final range = _getDateRangeForPeriod();

    final sessions = groupReadingActivities(
      _dataStore!.effectiveReadingActivities.where(
        (activity) =>
            activity.kind == 'reading' &&
            activity.endTime.isAfter(range.start) &&
            activity.startTime.isBefore(range.end),
      ),
    );

    return SessionStats(
      totalSessions: sessions.length,
      totalMinutes: totalReadingMinutes,
      totalPages: pagesRead,
      totalSeconds: totalReadingSeconds,
    );
  }

  List<StatisticsActivity> get readingTimeData => _readingTimeData;
  List<StatisticsActivity> get pagesReadData => _pagesReadData;
  List<MonthlyStats> get monthlyStats => _monthlyStats;
  List<GenreStats> get genreDistribution => _genreDistribution;
  ReadingStreak get streak => _streak;

  /// Total reading time formatted (e.g., "3.5h").
  String get totalReadingLabel {
    if (totalReadingSeconds > 0 && totalReadingSeconds < 60) {
      return '${totalReadingSeconds}s';
    }

    final hours = totalReadingMinutes / 60;

    if (hours < 1) {
      return '${totalReadingMinutes}m';
    }

    if (hours == hours.truncate()) {
      return '${hours.truncate()}h';
    }

    return '${hours.toStringAsFixed(1)}h';
  }

  /// Includes every calendar day in the selected period, including today.
  String get averageReadingLabel {
    final seconds = (totalReadingSeconds / periodDays).round();

    if (seconds > 0 && seconds < 60) {
      return '${seconds}s';
    }

    final minutes = (seconds / 60).round();
    return minutes < 60 ? '${minutes}m' : '${(minutes / 60).toStringAsFixed(1)}h';
  }

  int get averageDailyMinutes => (totalReadingSeconds / 60 / periodDays).round();

  /// Period label for display.
  String get periodLabel {
    switch (_selectedPeriod) {
      case StatsPeriod.week:
        return 'This week';
      case StatsPeriod.month:
        return 'This month';
      case StatsPeriod.year:
        return 'This year';
      case StatsPeriod.allTime:
        return 'All time';
      case StatsPeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${_formatShortDate(_customStartDate!)} - ${_formatShortDate(_customEndDate!)}';
        }
        return 'Custom range';
    }
  }

  /// Short period label for dropdown.
  String get periodShortLabel {
    switch (_selectedPeriod) {
      case StatsPeriod.week:
        return 'Week';
      case StatsPeriod.month:
        return 'Month';
      case StatsPeriod.year:
        return 'Year';
      case StatsPeriod.allTime:
        return 'All';
      case StatsPeriod.custom:
        return 'Custom';
    }
  }

  /// Whether custom date range is active.
  bool get hasCustomRange =>
      _selectedPeriod == StatsPeriod.custom && _customStartDate != null && _customEndDate != null;

  /// Loads statistics data. With DataStore, this is mainly for loading state UX.
  Future<void> loadStatistics() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _updateDataForPeriod();
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _error = 'Failed to load statistics: $error';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the selected time period and reloads data.
  void setPeriod(StatsPeriod period) {
    if (_selectedPeriod != period) {
      _selectedPeriod = period;

      if (period != StatsPeriod.custom) {
        _customStartDate = null;
        _customEndDate = null;
      }

      _updateDataForPeriod();
      notifyListeners();
    }
  }

  /// Sets a custom date range.
  void setCustomDateRange(DateTime startDate, DateTime endDate) {
    _selectedPeriod = StatsPeriod.custom;
    _customStartDate = startDate;
    _customEndDate = endDate;
    _updateDataForPeriod();
    notifyListeners();
  }

  /// Refreshes statistics data.
  Future<void> refresh() async {
    await loadStatistics();
  }

  ({DateTime start, DateTime end}) _getDateRangeForPeriod() {
    final now = _now();

    switch (_selectedPeriod) {
      case StatsPeriod.week:
        final weekStart = DateTime(now.year, now.month, now.day - now.weekday + 1);
        return (
          start: DateTime(weekStart.year, weekStart.month, weekStart.day),
          end: DateTime(now.year, now.month, now.day + 1),
        );
      case StatsPeriod.month:
        return (start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.year:
        return (start: DateTime(now.year, 1, 1), end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.allTime:
        final trackedBooks = {
          for (final activity in _dataStore?.readingActivities ?? <ReadingActivity>[])
            if (activity.kind == 'completion') activity.bookId,
        };

        final dates = <DateTime>[
          for (final activity in _dataStore?.effectiveReadingActivities ?? <ReadingActivity>[])
            activity.startTime.toLocal(),
          for (final book in _dataStore?.books ?? [])
            if (book.completedAt != null && !trackedBooks.contains(book.id)) book.completedAt!.toLocal(),
        ].where((date) => !date.isAfter(now)).toList()..sort();
        final first = dates.isEmpty ? now : dates.first;
        return (start: DateTime(first.year, first.month, first.day), end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return (
            start: DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day),
            end: DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day + 1),
          );
        }
        return (start: DateTime(now.year, now.month, now.day - 7), end: DateTime(now.year, now.month, now.day + 1));
    }
  }

  ({DateTime start, DateTime end}) _getChartDateRange() {
    final range = _getDateRangeForPeriod();
    final start = range.start;
    final end = switch (_selectedPeriod) {
      StatsPeriod.week => DateTime(start.year, start.month, start.day + 7),
      StatsPeriod.month => DateTime(start.year, start.month + 1),
      StatsPeriod.year => DateTime(start.year + 1),
      StatsPeriod.allTime || StatsPeriod.custom => range.end,
    };

    return (start: start, end: end);
  }

  void _updateDataForPeriod() {
    final range = _getDateRangeForPeriod();
    _periodTotals = _dataStore?.activityTotals(range.start, range.end);
    final readBookIds = _readBookIds;
    final genres = <String, int>{};

    for (final bookId in readBookIds) {
      final genre = _dataStore?.getBook(bookId)?.genre ?? 'Unspecified';
      genres.update(genre, (count) => count + 1, ifAbsent: () => 1);
    }

    final count = genres.values.fold<int>(0, (total, value) => total + value);

    _genreDistribution = genres.entries
        .map((entry) => GenreStats(genre: entry.key, bookCount: entry.value, percentage: entry.value / count))
        .toList();

    final now = _now();
    final qualified = _dataStore?.activityTotals(DateTime.utc(1900), now.toUtc()).qualifiedDays.toList() ?? [];
    qualified.sort();
    var best = 0;
    var run = 0;
    DateTime? previous;

    for (final day in qualified) {
      run = previous != null && GoalCalendar.nextDay(previous, GoalCalendar.systemTimezone) == day ? run + 1 : 1;

      if (run > best) {
        best = run;
      }

      previous = day;
    }

    final days = qualified.toSet();
    var cursor = GoalCalendar.midnight(now, GoalCalendar.systemTimezone);

    if (!days.contains(cursor)) {
      cursor = GoalCalendar.dayOffset(cursor, -1, GoalCalendar.systemTimezone);
    }

    var current = 0;

    while (days.contains(cursor)) {
      current++;
      cursor = GoalCalendar.dayOffset(cursor, -1, GoalCalendar.systemTimezone);
    }

    final local = GoalCalendar.local(now, GoalCalendar.systemTimezone);

    _streak = ReadingStreak(
      currentStreak: current,
      bestStreak: best,
      daysThisMonth: qualified.where((date) {
        final day = GoalCalendar.local(date, GoalCalendar.systemTimezone);
        return day.year == local.year && day.month == local.month;
      }).length,
      totalDaysInMonth: DateTime(local.year, local.month + 1, 0).day,
    );

    _monthlyStats = _generateMonthlyStats();
    _readingTimeData = _generateActivityData();
    _pagesReadData = _readingTimeData;
  }

  List<StatisticsActivity> _generateActivityData() {
    final store = _dataStore;

    if (store == null) {
      return [];
    }

    final range = _getChartDateRange();
    final elapsedEnd = _getDateRangeForPeriod().end;
    final size = bucketSize;
    final activities = <StatisticsActivity>[];
    var cursor = range.start;

    while (cursor.isBefore(range.end)) {
      final boundary = switch (size) {
        StatisticsBucketSize.day => DateTime(cursor.year, cursor.month, cursor.day + 1),
        StatisticsBucketSize.month => DateTime(cursor.year, cursor.month + 1),
        StatisticsBucketSize.year => DateTime(cursor.year + 1),
      };

      final end = boundary.isAfter(range.end) ? range.end : boundary;
      final dataEnd = end.isAfter(elapsedEnd) ? elapsedEnd : end;
      final totals = cursor.isBefore(dataEnd) ? store.activityTotals(cursor, dataEnd) : null;

      activities.add(
        StatisticsActivity(
          date: cursor,
          endDate: end,
          seconds: totals?.seconds ?? 0,
          pages: totals?.pages ?? 0,
          bucketSize: size,
          booksRead: cursor.isBefore(dataEnd) ? _completedBooks(cursor, dataEnd).toList() : const [],
        ),
      );

      cursor = end;
    }

    return activities;
  }

  List<MonthlyStats> _generateMonthlyStats() {
    final range = _getDateRangeForPeriod();
    final months = <MonthlyStats>[];
    var cursor = range.start;

    while (cursor.isBefore(range.end)) {
      final boundary = DateTime(cursor.year, cursor.month + 1);
      final end = boundary.isAfter(range.end) ? range.end : boundary;
      final totals = _dataStore?.activityTotals(cursor, end);

      months.add(
        MonthlyStats(
          month: cursor.month,
          year: cursor.year,
          booksRead: _completedBooks(cursor, end).length,
          pagesRead: totals?.pages.floor() ?? 0,
          readingMinutes: (totals?.seconds ?? 0) ~/ 60,
        ),
      );

      cursor = end;
    }

    return months;
  }

  String _formatShortDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
