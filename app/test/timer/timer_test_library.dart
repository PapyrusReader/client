import 'dart:async';

import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/reading_timer_repository.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/timer/reading_timer.dart';

class TimerTestLibrary extends InMemoryBookRepository implements TrackingRepositoryOwner {
  @override
  final TimerTestRepository trackingRepository = TimerTestRepository();
}

class TimerTestRepository implements TrackingRepository, ReadingTimerRepository {
  @override
  bool isCurrent = true;
  ReadingTimer? timer;
  int? savedPage;
  int? savedSeconds;
  bool failWrite = false;
  bool failLoad = false;
  int saves = 0;
  Completer<void>? writeGate;
  Completer<ReadingTimer?>? loadGate;
  final changes = StreamController<ReadingTimer?>.broadcast();

  @override
  Future<ReadingTimer?> loadTimer() async {
    if (failLoad) {
      throw StateError('Load failed. Try again.');
    }

    return loadGate == null ? timer : await loadGate!.future;
  }

  @override
  Stream<ReadingTimer?> watchTimer() async* {
    yield await loadTimer();
    yield* changes.stream;
  }

  @override
  Future<void> writeTimer(ReadingTimer value, {ReadingTimer? previous}) async {
    await writeGate?.future;

    if (failWrite) {
      throw StateError('Save failed. Try again.');
    }

    if (!isCurrent) {
      throw StateError('Library changed.');
    }

    timer = value;
    changes.add(timer);
  }

  @override
  Future<void> discardTimer(ReadingTimer timer) async {
    this.timer = null;
    changes.add(null);
  }

  @override
  Future<void> finishTimer(ReadingTimer timer, DateTime now, {int? currentPage}) async {
    if (failWrite) {
      throw StateError('Save failed. Try again.');
    }

    saves++;
    savedPage = currentPage;
    savedSeconds = timer.elapsed(now).inSeconds;
    this.timer = null;
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
