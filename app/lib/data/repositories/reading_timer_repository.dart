import 'package:papyrus/timer/reading_timer.dart';

/// Captured per library so an in-flight operation cannot follow an account switch.
abstract interface class ReadingTimerRepository {
  bool get isCurrent;
  Future<ReadingTimer?> loadTimer();
  Stream<ReadingTimer?> watchTimer();
  Future<void> writeTimer(ReadingTimer timer, {ReadingTimer? previous});
  Future<void> discardTimer(ReadingTimer timer);
  Future<void> finishTimer(ReadingTimer timer, DateTime now, {int? currentPage});
}
