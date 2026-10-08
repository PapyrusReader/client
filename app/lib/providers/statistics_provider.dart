import 'package:flutter/foundation.dart';
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

  const SessionStats({required this.totalSessions, required this.totalMinutes, required this.totalPages});

  /// Average session duration in minutes.
  double get averageSessionDuration => totalSessions > 0 ? totalMinutes / totalSessions : 0;

  /// Reading velocity (pages per hour).
  double get pagesPerHour => totalMinutes > 0 ? (totalPages / totalMinutes) * 60 : 0;

  /// Formatted average session duration.
  String get averageSessionLabel {
    final avg = averageSessionDuration.round();
    if (avg < 60) return '${avg}m';
    final hours = avg ~/ 60;
    final minutes = avg % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  /// Formatted reading velocity.
  String get velocityLabel => '${pagesPerHour.toStringAsFixed(1)} pages/hr';
}

/// Provider for statistics page state management.
/// Uses DataStore as the single source of truth.
class StatisticsProvider extends ChangeNotifier {
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
  List<DailyActivity> _readingTimeData = [];
  List<DailyActivity> _pagesReadData = [];
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

  // ============================================================================
  // GETTERS
  // ============================================================================

  bool get isLoading => _isLoading;
  String? get error => _error;

  StatsPeriod get selectedPeriod => _selectedPeriod;
  DateTime? get customStartDate => _customStartDate;
  DateTime? get customEndDate => _customEndDate;

  /// Total books completed in the selected period.
  int get totalBooks {
    if (_dataStore == null) return 0;
    final range = _getDateRangeForPeriod();
    return _completedBooks(range.start, range.end).length;
  }

  Set<String> _completedBooks(DateTime start, DateTime end) {
    final store = _dataStore;
    if (store == null) return {};
    final trackedBooks = store.readingActivities.where((a) => a.kind == 'completion').map((a) => a.bookId).toSet();
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
    if (_dataStore == null) return 0;
    final range = _getDateRangeForPeriod();
    final now = DateTime.now().toUtc();
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

  /// Total reading minutes in the selected period.
  int get totalReadingMinutes {
    if (_dataStore == null) return 0;
    final range = _getDateRangeForPeriod();
    return _dataStore!.activityTotals(range.start, range.end).seconds ~/ 60;
  }

  /// Pages read in the selected period.
  int get pagesRead {
    if (_dataStore == null) return 0;
    final range = _getDateRangeForPeriod();
    return _dataStore!.activityTotals(range.start, range.end).pages.floor();
  }

  /// Session statistics for the selected period.
  SessionStats get sessionStats {
    if (_dataStore == null) {
      return const SessionStats(totalSessions: 0, totalMinutes: 0, totalPages: 0);
    }
    final range = _getDateRangeForPeriod();
    final sessions = groupReadingActivities(
      _dataStore!.effectiveReadingActivities.where(
        (s) => s.kind == 'reading' && s.endTime.isAfter(range.start) && s.startTime.isBefore(range.end),
      ),
    );
    return SessionStats(totalSessions: sessions.length, totalMinutes: totalReadingMinutes, totalPages: pagesRead);
  }

  List<DailyActivity> get readingTimeData => _readingTimeData;
  List<DailyActivity> get pagesReadData => _pagesReadData;
  List<MonthlyStats> get monthlyStats => _monthlyStats;
  List<GenreStats> get genreDistribution => _genreDistribution;
  ReadingStreak get streak => _streak;

  // ============================================================================
  // COMPUTED PROPERTIES
  // ============================================================================

  /// Total reading time formatted (e.g., "3.5h").
  String get totalReadingLabel {
    final hours = totalReadingMinutes / 60;
    if (hours < 1) return '${totalReadingMinutes}m';
    if (hours == hours.truncate()) return '${hours.truncate()}h';
    return '${hours.toStringAsFixed(1)}h';
  }

  /// Average reading time per day for the period.
  String get averageReadingLabel {
    if (_readingTimeData.isEmpty) return '0m';
    final avgMinutes = _readingTimeData.averageMinutes;
    if (avgMinutes < 60) return '${avgMinutes}m';
    final hours = avgMinutes / 60;
    return '${hours.toStringAsFixed(1)}h';
  }

  /// Average daily reading time in minutes.
  int get averageDailyMinutes {
    if (_readingTimeData.isEmpty) return 0;
    return _readingTimeData.averageMinutes;
  }

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

  // ============================================================================
  // METHODS
  // ============================================================================

  /// Loads statistics data. With DataStore, this is mainly for loading state UX.
  Future<void> loadStatistics() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Simulate network delay for realistic UX
      await Future.delayed(const Duration(milliseconds: 100));

      _updateDataForPeriod();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load statistics: $e';
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

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  ({DateTime start, DateTime end}) _getDateRangeForPeriod() {
    final now = DateTime.now();
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
        return (start: DateTime(2000), end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return (
            start: _customStartDate!,
            end: DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day + 1),
          );
        }
        return (start: DateTime(now.year, now.month, now.day - 7), end: DateTime(now.year, now.month, now.day + 1));
    }
  }

  void _updateDataForPeriod() {
    final books = _dataStore?.books ?? [];
    final genres = <String, int>{};
    for (final book in books) {
      final genre = book.customMetadata?['genre'];
      if (genre is String && genre.trim().isNotEmpty) genres.update(genre.trim(), (n) => n + 1, ifAbsent: () => 1);
    }
    final count = genres.values.fold<int>(0, (a, b) => a + b);
    _genreDistribution = genres.entries
        .map((e) => GenreStats(genre: e.key, bookCount: e.value, percentage: e.value / count))
        .toList();
    final now = DateTime.now();
    final qualified = _dataStore?.activityTotals(DateTime.utc(1900), now.toUtc()).qualifiedDays.toList() ?? [];
    qualified.sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in qualified) {
      run = previous != null && GoalCalendar.nextDay(previous, GoalCalendar.systemTimezone) == day ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }
    final days = qualified.toSet();
    var cursor = GoalCalendar.midnight(now, GoalCalendar.systemTimezone);
    if (!days.contains(cursor)) cursor = GoalCalendar.dayOffset(cursor, -1, GoalCalendar.systemTimezone);
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = GoalCalendar.dayOffset(cursor, -1, GoalCalendar.systemTimezone);
    }
    final local = GoalCalendar.local(now, GoalCalendar.systemTimezone);
    _streak = ReadingStreak(
      currentStreak: current,
      bestStreak: best,
      daysThisMonth: qualified.where((d) {
        final day = GoalCalendar.local(d, GoalCalendar.systemTimezone);
        return day.year == local.year && day.month == local.month;
      }).length,
      totalDaysInMonth: DateTime(local.year, local.month + 1, 0).day,
    );
    _monthlyStats = _generateMonthlyStats();
    _readingTimeData = _generateActivityData();
    _pagesReadData = _readingTimeData;
  }

  List<DailyActivity> _generateActivityData() {
    if (_dataStore == null) return [];
    final range = _getDateRangeForPeriod();
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final count = end.difference(range.start).inDays.clamp(1, 60);
    final first = DateTime(end.year, end.month, end.day - count);
    return List.generate(count, (i) {
      final day = DateTime(first.year, first.month, first.day + i);
      final totals = _dataStore!.activityTotals(day, DateTime(day.year, day.month, day.day + 1));
      return DailyActivity(
        date: day,
        readingMinutes: totals.seconds ~/ 60,
        pagesRead: totals.pages.floor(),
        booksRead: _completedBooks(day, DateTime(day.year, day.month, day.day + 1)).toList(),
      );
    });
  }

  List<MonthlyStats> _generateMonthlyStats() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final start = DateTime(now.year, now.month - i);
      final end = DateTime(start.year, start.month + 1);
      final totals = _dataStore?.activityTotals(start, end);
      return MonthlyStats(
        month: start.month,
        year: start.year,
        booksRead: _completedBooks(start, end).length,
        pagesRead: totals?.pages.floor() ?? 0,
        readingMinutes: (totals?.seconds ?? 0) ~/ 60,
      );
    }).reversed.toList();
  }

  String _formatShortDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
