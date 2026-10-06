import 'package:papyrus/services/reading_device_identity.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/goals/goal_progress.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/goal_period_record.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';

class GoalsProvider extends ChangeNotifier {
  GoalsProvider({DateTime Function()? now, this.watchClock = true}) : _now = now ?? DateTime.now;
  final bool watchClock;
  final DateTime Function() _now;
  DataStore? _store;
  bool _sealing = false;
  String? _error;
  Timer? _clock;
  DataStore get store => _store!;
  String? get error => _error;
  bool get isLoading => _store?.isLoaded != true;
  DateTime get now => _now().toUtc();
  void attach(DataStore dataStore) {
    if (identical(_store, dataStore)) return;
    _store?.removeListener(_changed);
    _store = dataStore;
    dataStore.addListener(_changed);
    if (watchClock) _clock ??= Timer.periodic(const Duration(minutes: 1), (_) => _changed());
    // Attaching from a page's dependency update must not persist periods and
    // notify the DataStore's listeners while that page is still building.
    scheduleMicrotask(() {
      if (identical(_store, dataStore)) _changed();
    });
  }

  void _changed() {
    notifyListeners();
    if (!_sealing && _store?.isLoaded == true) unawaited(_sealPeriods());
  }

  List<GoalProgress> get current => store.goalDefinitions
      .where((goal) => !goal.isArchived)
      .map((goal) => projectGoal(goal, store.readingActivities, now))
      .where((progress) => progress.range.end.isAfter(now))
      .toList();
  List<ReadingGoal> get activeGoals => current.map((progress) => progress.projected).toList();
  List<ReadingGoal> get completedGoals => store.goalDefinitions.where((goal) => goal.isArchived).toList();
  bool get hasActiveGoals => current.isNotEmpty;
  bool get hasCompletedGoals => store.goalPeriods.isNotEmpty || completedGoals.isNotEmpty;
  GoalProgress progress(ReadingGoal goal) => projectGoal(goal, store.readingActivities, now);
  List<GoalProgress> get history {
    final all = <String, GoalProgress>{};
    for (final goal in store.goalDefinitions) {
      for (final period in GoalCalendar.pastPeriods(goal, now)) {
        all['${goal.id}:${period.start}'] = projectGoal(goal, store.readingActivities, now, period: period);
      }
    }
    for (final record in store.goalPeriods) {
      all['${record.goalId}:${record.definition.startDate}'] = projectGoal(
        store.getReadingGoal(record.goalId) ?? record.definition,
        store.readingActivities,
        now,
        period: GoalRange(record.definition.startDate, record.definition.endDate),
      );
    }
    final values = all.values.toList()..sort((a, b) => b.range.end.compareTo(a.range.end));
    return values;
  }

  Future<void> _sealPeriods() async {
    _sealing = true;
    final target = store.trackingRepository;
    try {
      final known = store.goalPeriods.map((value) => value.id).toSet();
      final records = <GoalPeriodRecord>[];
      for (final goal in store.goalDefinitions) {
        for (final period in GoalCalendar.pastPeriods(goal, now)) {
          final id = const Uuid().v5(
            Namespace.url.value,
            'papyrus:goal-period:${goal.id}:${period.start.microsecondsSinceEpoch}',
          );
          if (known.contains(id)) continue;
          final rule = ruleAt(goal, period.end.subtract(const Duration(microseconds: 1)));
          final definition = goal.copyWith(
            startDate: period.start,
            endDate: period.end,
            targetValue: rule.target,
            title: rule.title,
            isActive: rule.active,
            isArchived: rule.archived,
            isRecurring: false,
            rules: goal.rules.where((rule) => rule.at.isBefore(period.end)).toList(),
          );
          records.add(GoalPeriodRecord(id: id, goalId: goal.id, definition: definition));
        }
      }
      if (records.isNotEmpty) await store.commitTracking(periods: records, repository: target);
      _error = null;
    } catch (error) {
      _error = 'Could not save goal history: $error';
    } finally {
      _sealing = false;
    }
  }

  Future<void> loadGoals() => store.waitUntilLoaded();
  Future<void> refresh() => _sealPeriods();
  Future<void> createGoal({
    required GoalType type,
    required int target,
    required GoalPeriod period,
    bool isRecurring = true,
    DateTime? startDate,
    DateTime? endDate,
    String? title,
    GoalScope scope = GoalScope.library,
    String? scopeId,
    int minimumMinutes = 5,
    String? timezone,
    String? replaceGoalId,
    TrackingRepository? repository,
  }) async {
    final origin = repository ?? store.trackingRepository;
    final replacing = replaceGoalId == null ? null : store.getReadingGoal(replaceGoalId);
    if (replaceGoalId != null && replacing == null) throw StateError('This goal no longer exists.');
    if (target < 1 || minimumMinutes < 1 || minimumMinutes > 1440) throw ArgumentError('Targets must be positive.');
    if (scope != GoalScope.library && scopeId == null) throw ArgumentError('Choose a book or shelf.');
    final zone = timezone ?? await GoalCalendar.deviceTimezone();
    final created = now;
    final range = period == GoalPeriod.custom
        ? GoalRange(startDate ?? created, endDate ?? GoalCalendar.nextDay(created.add(const Duration(days: 30)), zone))
        : GoalCalendar.calendarPeriod(period, created, zone);
    if (!range.end.isAfter(created)) throw ArgumentError('The deadline must be in the future.');
    final goal = ReadingGoal(
      id: const Uuid().v4(),
      type: type,
      targetValue: target,
      period: period,
      startDate: range.start,
      endDate: range.end,
      createdAt: created,
      title: title?.trim().isEmpty == true ? null : title,
      timezone: zone,
      scope: scope,
      scopeId: scopeId,
      minimumMinutes: minimumMinutes,
      isRecurring: period != GoalPeriod.custom && isRecurring,
      rules: [GoalRule(at: created, target: target, title: title?.trim().isEmpty == true ? null : title)],
    );
    await store.commitTracking(
      goals: [if (replacing != null) _revisedGoal(replacing, archived: true, active: false), goal],
      repository: origin,
    );
  }

  Future<void> updateGoal({
    required String goalId,
    int? target,
    String? title,
    GoalType? type,
    TrackingRepository? repository,
  }) async {
    final goal = store.getReadingGoal(goalId);
    if (goal == null) throw StateError('This goal no longer exists.');
    if (type != null && type != goal.type) {
      await createGoal(
        type: type,
        target: target ?? goal.targetValue,
        period: goal.period,
        isRecurring: goal.isRecurring,
        endDate: goal.endDate,
        title: title ?? goal.title,
        scope: goal.scope,
        scopeId: goal.scopeId,
        minimumMinutes: goal.minimumMinutes,
        timezone: goal.timezone,
        replaceGoalId: goalId,
        repository: repository,
      );
      return;
    }
    if (target != null && target < 1) throw ArgumentError('Target must be positive.');
    await _revise(goal, target: target, title: title, repository: repository);
  }

  Future<void> _revise(
    ReadingGoal goal, {
    int? target,
    String? title,
    bool? active,
    bool? archived,
    TrackingRepository? repository,
  }) => store.commitTracking(
    goals: [_revisedGoal(goal, target: target, title: title, active: active, archived: archived)],
    repository: repository,
  );

  ReadingGoal _revisedGoal(ReadingGoal goal, {int? target, String? title, bool? active, bool? archived}) {
    var at = now;
    final rules = goal.rules.isEmpty
        ? [
            GoalRule(
              at: goal.createdAt,
              target: goal.targetValue,
              title: goal.title,
              active: goal.isActive,
              archived: goal.isArchived,
            ),
          ]
        : [...goal.rules];
    if (!at.isAfter(rules.last.at)) at = rules.last.at.add(const Duration(microseconds: 1));
    final rule = GoalRule(
      at: at,
      target: target ?? goal.targetValue,
      title: title ?? goal.title,
      active: active ?? goal.isActive,
      archived: archived ?? goal.isArchived,
    );
    return goal.copyWith(
      targetValue: rule.target,
      title: rule.title,
      isActive: rule.active,
      isArchived: rule.archived,
      rules: [...rules, rule],
    );
  }

  Future<void> pauseGoal(String id, bool paused, {TrackingRepository? repository}) =>
      _revise(store.getReadingGoal(id)!, active: !paused, repository: repository);
  Future<void> archiveGoal(String id, {TrackingRepository? repository}) =>
      _revise(store.getReadingGoal(id)!, archived: true, active: false, repository: repository);
  Future<void> restoreGoal(String id, {TrackingRepository? repository}) =>
      _revise(store.getReadingGoal(id)!, archived: false, active: true, repository: repository);
  Future<void> deleteGoal(String id, {TrackingRepository? repository}) async {
    await _sealPeriods();
    final goal = store.getReadingGoal(id);
    if (goal == null) return;
    final period = GoalCalendar.currentPeriod(goal, now);
    final record = GoalPeriodRecord(
      id: const Uuid().v5(Namespace.url.value, 'papyrus:goal-period:$id:${period.start.microsecondsSinceEpoch}'),
      goalId: id,
      definition: goal.copyWith(
        startDate: period.start,
        endDate: now.isBefore(period.end) ? now : period.end,
        isRecurring: false,
        isArchived: true,
        isActive: false,
        rules: [
          ...goal.rules,
          GoalRule(
            at: goal.rules.isNotEmpty && !now.isAfter(goal.rules.last.at)
                ? goal.rules.last.at.add(const Duration(microseconds: 1))
                : now,
            target: goal.targetValue,
            title: goal.title,
            active: false,
            archived: true,
          ),
        ],
      ),
    );
    await store.commitTracking(periods: [record], deleteGoalId: id, repository: repository);
  }

  Future<void> logReading({
    required Book book,
    required DateTime end,
    int minutes = 0,
    int pages = 0,
    bool finished = false,
    String? note,
    ReadingActivity? correcting,
    TrackingRepository? repository,
  }) async {
    if (end.isAfter(now) || minutes < 0 || pages < 0 || minutes == 0 && pages == 0 && !finished) {
      throw ArgumentError('Choose a past time and enter reading time, pages, or completion.');
    }
    final created = now;
    final shelfIds = correcting?.shelfIds ?? store.getShelfIdsForBook(book.id);
    final activities = <ReadingActivity>[
      if (correcting != null) store.reversalFor(correcting, note: 'Corrected entry'),
    ];
    if (minutes > 0 || pages > 0) {
      activities.add(
        ReadingActivity(
          id: const Uuid().v4(),
          bookId: book.id,
          bookTitle: book.title,
          startTime: end.subtract(Duration(minutes: minutes)),
          endTime: end,
          createdAt: created,
          deviceId: ReadingDeviceIdentity.current,
          pages: pages,
          shelfIds: shelfIds,
          note: note,
        ),
      );
    }
    if (finished) {
      activities.add(
        ReadingActivity(
          id: const Uuid().v4(),
          bookId: book.id,
          bookTitle: book.title,
          startTime: end,
          endTime: end,
          createdAt: created,
          deviceId: ReadingDeviceIdentity.current,
          kind: 'completion',
          shelfIds: shelfIds,
          note: note,
        ),
      );
    }
    final updated = finished
        ? book.copyWith(readingStatus: LibraryReadingStatus.completed, completedAt: end)
        : correcting?.kind == 'completion'
        ? book.copyWith(readingStatus: LibraryReadingStatus.inProgress, clearCompletedAt: true)
        : book.copyWith(lastReadAt: book.lastReadAt != null && book.lastReadAt!.isAfter(end) ? book.lastReadAt : end);
    await store.commitTracking(activities: activities, book: updated, previousBook: book, repository: repository);
  }

  Future<void> reverseActivity(ReadingActivity original, {TrackingRepository? repository}) async {
    final book = store.getBook(original.bookId);
    final anotherCompletion = store.effectiveReadingActivities.any(
      (activity) => activity.bookId == original.bookId && activity.kind == 'completion' && activity.id != original.id,
    );
    await store.commitTracking(
      activities: [
        for (final entry in store.effectiveReadingActivities.where(
          (a) => a.id == original.id || original.constituentIds.contains(a.id),
        ))
          store.reversalFor(entry, note: 'Undone from activity history'),
      ],
      book: original.kind == 'completion' && book?.readingStatus == LibraryReadingStatus.completed && !anotherCompletion
          ? book!.copyWith(readingStatus: LibraryReadingStatus.inProgress, clearCompletedAt: true)
          : null,
      previousBook: book,
      repository: repository,
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _store?.removeListener(_changed);
    _store = null;
    super.dispose();
  }
}
