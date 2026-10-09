import 'package:papyrus/models/reading_goal.dart';

/// Retains the definition used by a closed period, not an editable counter.
class GoalPeriodRecord {
  const GoalPeriodRecord({required this.id, required this.goalId, required this.definition});
  final String id;
  final String goalId;
  final ReadingGoal definition;
  Map<String, dynamic> toJson() => {'id': id, 'goal_id': goalId, 'definition': definition.toJson()};

  factory GoalPeriodRecord.fromJson(Map<String, dynamic> json) => GoalPeriodRecord(
    id: json['id'] as String,
    goalId: json['goal_id'] as String,
    definition: ReadingGoal.fromJson(Map<String, dynamic>.from(json['definition'] as Map)),
  );
}
