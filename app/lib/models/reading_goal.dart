String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

enum GoalType { books, pages, minutes, days }

enum GoalPeriod { daily, weekly, monthly, yearly, custom }

enum GoalScope { library, book, shelf }

String goalMetric(GoalType type) => switch (type) {
  GoalType.books => 'books_count',
  GoalType.pages => 'pages_count',
  GoalType.minutes => 'reading_time',
  GoalType.days => 'reading_days',
};
GoalType parseGoalMetric(String value) => switch (value) {
  'books_count' || 'books' => GoalType.books,
  'pages_count' || 'pages' => GoalType.pages,
  'reading_time' || 'minutes' => GoalType.minutes,
  'reading_days' || 'days' => GoalType.days,
  _ => throw FormatException('Unknown goal metric: $value'),
};

/// Rule revisions retain targets and pause/archive intervals across devices.
class GoalRule {
  const GoalRule({required this.at, required this.target, this.title, this.active = true, this.archived = false});
  final DateTime at;
  final int target;
  final String? title;
  final bool active;
  final bool archived;
  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'target': target,
    'title': title,
    'active': active,
    'archived': archived,
  };
  factory GoalRule.fromJson(Map<String, dynamic> json) => GoalRule(
    at: DateTime.parse(json['at'] as String).toUtc(),
    target: json['target'] as int,
    title: json['title'] as String?,
    active: json['active'] == true,
    archived: json['archived'] == true,
  );
}

/// Definition data is persisted; currentValue and streak are derived projections.
class ReadingGoal {
  final String id;
  final String? title;
  final String? goalDescription;
  final GoalType type;
  final int targetValue;
  final int currentValue;
  final GoalPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final String timezone;
  final GoalScope scope;
  final String? scopeId;
  final List<String> bookIds;
  final int minimumMinutes;
  final List<GoalRule> rules;
  final bool isActive;
  final bool isRecurring;
  final int streak;
  final bool isArchived;
  final DateTime? completedAt;
  final bool estimatedPages;
  const ReadingGoal({
    required this.id,
    this.title,
    this.goalDescription,
    required this.type,
    required this.targetValue,
    this.currentValue = 0,
    required this.period,
    required this.startDate,
    required this.endDate,
    DateTime? createdAt,
    this.timezone = 'UTC',
    this.scope = GoalScope.library,
    this.scopeId,
    this.bookIds = const [],
    this.minimumMinutes = 5,
    this.rules = const [],
    this.isActive = true,
    this.isRecurring = true,
    this.streak = 0,
    this.isArchived = false,
    this.completedAt,
    this.estimatedPages = false,
  }) : createdAt = createdAt ?? startDate;
  List<String> get selectedBookIds => scope != GoalScope.book
      ? const []
      : bookIds.isNotEmpty
      ? bookIds
      : [?scopeId];
  int get target => targetValue;
  int get current => currentValue;
  double get progress => targetValue == 0 ? 0 : (currentValue / targetValue).clamp(0.0, 1.0);
  int get remaining => (targetValue - currentValue).clamp(0, targetValue);
  bool get isCompleted => currentValue >= targetValue;
  String get progressLabel => '${(progress * 100).round()}%';
  String get typeLabel => unitLabel(2);
  String unitLabel(int quantity) => switch (type) {
    GoalType.books => quantity == 1 ? 'book' : 'books',
    GoalType.pages => quantity == 1 ? 'page' : 'pages',
    GoalType.minutes => quantity == 1 ? 'minute' : 'minutes',
    GoalType.days => quantity == 1 ? 'day' : 'days',
  };
  String get periodLabel => switch (period) {
    GoalPeriod.daily => 'daily',
    GoalPeriod.weekly => 'this week',
    GoalPeriod.monthly => 'this month',
    GoalPeriod.yearly => 'this year',
    GoalPeriod.custom => 'by ${endDate.day}/${endDate.month}/${endDate.year}',
  };
  bool get isDaily => period == GoalPeriod.daily;
  bool get isYearly => period == GoalPeriod.yearly;
  bool get isCustomPeriod => period == GoalPeriod.custom;
  String get description =>
      goalDescription ??
      (type == GoalType.days
          ? 'Read on $targetValue ${unitLabel(targetValue)} $periodLabel'
          : 'Read ${type == GoalType.minutes ? formatDuration(targetValue) : '$targetValue ${unitLabel(targetValue)}'} $periodLabel');
  String get displayTitle => title?.trim().isNotEmpty == true ? title! : description;
  String get statusText => isCompleted
      ? 'Target reached'
      : '${type == GoalType.minutes ? formatDuration(remaining) : '$remaining ${unitLabel(remaining)}'} to go';
  String get recurrenceLabel => isRecurring && !isCustomPeriod ? 'Recurring' : 'One-off';
  ReadingGoal copyWith({
    String? id,
    String? title,
    String? goalDescription,
    GoalType? type,
    int? targetValue,
    int? currentValue,
    GoalPeriod? period,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    String? timezone,
    GoalScope? scope,
    String? scopeId,
    List<String>? bookIds,
    int? minimumMinutes,
    List<GoalRule>? rules,
    bool? isActive,
    bool? isRecurring,
    int? streak,
    bool? isArchived,
    DateTime? completedAt,
    bool? estimatedPages,
  }) => ReadingGoal(
    id: id ?? this.id,
    title: title ?? this.title,
    goalDescription: goalDescription ?? this.goalDescription,
    type: type ?? this.type,
    targetValue: targetValue ?? this.targetValue,
    currentValue: currentValue ?? this.currentValue,
    period: period ?? this.period,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    createdAt: createdAt ?? this.createdAt,
    timezone: timezone ?? this.timezone,
    scope: scope ?? this.scope,
    scopeId: scopeId ?? this.scopeId,
    bookIds: bookIds ?? this.bookIds,
    minimumMinutes: minimumMinutes ?? this.minimumMinutes,
    rules: rules ?? this.rules,
    isActive: isActive ?? this.isActive,
    isRecurring: isRecurring ?? this.isRecurring,
    streak: streak ?? this.streak,
    isArchived: isArchived ?? this.isArchived,
    completedAt: completedAt ?? this.completedAt,
    estimatedPages: estimatedPages ?? this.estimatedPages,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': goalDescription,
    'goal_type': goalMetric(type),
    'target_value': targetValue,
    'time_period': period.name,
    'start_date': startDate.toUtc().toIso8601String(),
    'end_date': endDate.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'timezone': timezone,
    'scope': scope.name,
    'scope_id': scopeId,
    if (bookIds.length > 1) 'book_ids': bookIds,
    'minimum_minutes': minimumMinutes,
    'rules': rules.map((rule) => rule.toJson()).toList(),
    'is_active': isActive,
    'is_recurring': isRecurring,
    'is_archived': isArchived,
  };
  factory ReadingGoal.fromJson(Map<String, dynamic> json) => ReadingGoal(
    id: json['id'] as String,
    title: json['title'] as String?,
    goalDescription: json['description'] as String?,
    type: parseGoalMetric(json['goal_type'] as String),
    targetValue: json['target_value'] as int,
    currentValue: json['current_value'] as int? ?? 0,
    period: GoalPeriod.values.byName(json['time_period'] as String),
    startDate: DateTime.parse(json['start_date'] as String).toUtc(),
    endDate: DateTime.parse(json['end_date'] as String).toUtc(),
    createdAt: DateTime.parse((json['created_at'] ?? json['start_date']) as String).toUtc(),
    timezone: json['timezone'] as String? ?? 'UTC',
    scope: GoalScope.values.byName(json['scope'] as String? ?? 'library'),
    scopeId: json['scope_id'] as String?,
    bookIds: (json['book_ids'] as List? ?? []).cast<String>(),
    minimumMinutes: json['minimum_minutes'] as int? ?? 5,
    rules: (json['rules'] as List? ?? [])
        .map((value) => GoalRule.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList(),
    isActive: json['is_active'] as bool? ?? true,
    isRecurring: json['is_recurring'] as bool? ?? true,
    isArchived: json['is_archived'] as bool? ?? false,
    streak: json['streak'] as int? ?? 0,
    completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
  );

  /// Sample reading goals for backwards compatibility.
  static List<ReadingGoal> get sampleGoals {
    final now = DateTime.now();
    return [
      ReadingGoal(
        id: 'goal-1',
        title: 'Yearly reading goal',
        type: GoalType.books,
        targetValue: 12,
        currentValue: 3,
        period: GoalPeriod.yearly,
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
        isActive: true,
        isRecurring: true,
      ),
      ReadingGoal(
        id: 'goal-2',
        title: 'Daily reading habit',
        type: GoalType.minutes,
        targetValue: 30,
        currentValue: 45,
        period: GoalPeriod.daily,
        startDate: DateTime(now.year, now.month, now.day),
        endDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
        isActive: true,
        isRecurring: true,
        streak: 5,
      ),
      ReadingGoal(
        id: 'goal-3',
        title: 'Weekly pages',
        type: GoalType.pages,
        targetValue: 100,
        currentValue: 65,
        period: GoalPeriod.weekly,
        startDate: now.subtract(Duration(days: now.weekday - 1)),
        endDate: now.add(Duration(days: 7 - now.weekday)),
        isActive: true,
        isRecurring: false,
      ),
      ReadingGoal(
        id: 'goal-4',
        title: 'Summer reading challenge',
        goalDescription: 'Read 5 books during summer vacation',
        type: GoalType.books,
        targetValue: 5,
        currentValue: 2,
        period: GoalPeriod.custom,
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 2, 0),
        isActive: true,
        isRecurring: false,
      ),
    ];
  }

  /// Sample completed goals for backwards compatibility.
  static List<ReadingGoal> get sampleCompletedGoals {
    final now = DateTime.now();
    return [
      ReadingGoal(
        id: 'goal-5',
        title: 'Q1 reading goal',
        type: GoalType.books,
        targetValue: 6,
        currentValue: 6,
        period: GoalPeriod.custom,
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 3, 31),
        isActive: false,
        isRecurring: false,
        isArchived: true,
        completedAt: DateTime(now.year, 3, 15),
      ),
      ReadingGoal(
        id: 'goal-6',
        title: 'Last year reading time',
        type: GoalType.minutes,
        targetValue: 6000,
        currentValue: 6000,
        period: GoalPeriod.yearly,
        startDate: DateTime(now.year - 1, 1, 1),
        endDate: DateTime(now.year - 1, 12, 31),
        isActive: false,
        isRecurring: true,
        isArchived: true,
        completedAt: DateTime(now.year - 1, 12, 20),
      ),
    ];
  }
}
