import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/goal_period_record.dart';

/// Capture this handle when opening a reader or sheet; never follow profile switches.
abstract interface class TrackingRepository {
  bool get isCurrent;

  Future<void> commitTracking({
    List<ReadingGoal> goals = const [],
    List<ReadingActivity> activities = const [],
    List<GoalPeriodRecord> periods = const [],
    String? deleteGoalId,
    Book? book,
    Book? previousBook,
    String? readerBookId,
    Map<String, dynamic>? readerPatch,
  });
}

abstract interface class TrackingRepositoryOwner {
  TrackingRepository get trackingRepository;
}
