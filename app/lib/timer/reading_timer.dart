import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:uuid/uuid.dart';

enum ReadingTimerPhase { running, paused, finished }

class ReadingInterval {
  const ReadingInterval(this.start, this.end);

  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => {'start': start.toIso8601String(), 'end': end.toIso8601String()};

  factory ReadingInterval.fromJson(Map<String, dynamic> json) =>
      ReadingInterval(DateTime.parse(json['start'] as String), DateTime.parse(json['end'] as String));
}

/// Timestamp-based state shared across devices. Ticks are calculated locally.
class ReadingTimer {
  const ReadingTimer({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.startedAt,
    required this.deviceId,
    required this.shelfIds,
    required this.startPage,
    required this.phase,
    this.targetSeconds,
    this.runningSince,
    this.intervals = const [],
    this.revision = 0,
    this.versionToken,
  });

  factory ReadingTimer.start(Book book, DateTime now, String deviceId, List<String> shelfIds, {int? targetSeconds}) {
    if (targetSeconds != null && (targetSeconds < 60 || targetSeconds > 86400)) {
      throw ArgumentError('Choose a duration from 1 minute to 24 hours.');
    }

    return ReadingTimer(
      id: const Uuid().v4(),
      bookId: book.id,
      bookTitle: book.title,
      startedAt: now.toUtc(),
      runningSince: now.toUtc(),
      deviceId: deviceId,
      shelfIds: List.unmodifiable(shelfIds),
      startPage: book.currentPage ?? 0,
      targetSeconds: targetSeconds,
      phase: ReadingTimerPhase.running,
    );
  }

  final String id;
  final String bookId;
  final String bookTitle;
  final DateTime startedAt;
  final String deviceId;
  final List<String> shelfIds;
  final int startPage;
  final int? targetSeconds;
  final ReadingTimerPhase phase;
  final DateTime? runningSince;
  final List<ReadingInterval> intervals;
  final int revision;
  final String? versionToken;
  String get version => versionToken ?? '$id:$revision';

  Duration get recorded => intervals.fold(Duration.zero, (total, interval) => total + interval.duration);

  DateTime? intervalEnd(DateTime now) {
    final start = runningSince;

    if (start == null) {
      return null;
    }

    var end = now.toUtc().isBefore(start) ? start : now.toUtc();
    final target = targetSeconds;

    if (target != null) {
      final deadline = start.add(Duration(seconds: target) - recorded);

      if (end.isAfter(deadline)) {
        end = deadline;
      }
    }

    return end;
  }

  Duration elapsed(DateTime now) {
    final end = intervalEnd(now);
    return recorded + (end == null ? Duration.zero : end.difference(runningSince!));
  }

  bool reachedGoal(DateTime now) => targetSeconds != null && elapsed(now).inSeconds >= targetSeconds!;
  bool isRunning(DateTime now) => phase == ReadingTimerPhase.running && !reachedGoal(now);

  ReadingTimer stop(DateTime now, {bool finish = false}) {
    final end = intervalEnd(now);

    return _copy(
      phase: finish || reachedGoal(now) ? ReadingTimerPhase.finished : ReadingTimerPhase.paused,
      intervals: [
        ...intervals,
        if (end != null && end.isAfter(runningSince!)) ReadingInterval(runningSince!, end),
      ],
    );
  }

  ReadingTimer resume(DateTime now, {bool keepReading = false}) {
    final earliest = intervals.isEmpty ? startedAt : intervals.last.end;
    final requested = now.toUtc();

    return _copy(
      phase: ReadingTimerPhase.running,
      runningSince: requested.isBefore(earliest) ? earliest : requested,
      clearTarget: keepReading,
    );
  }

  ReadingTimer _copy({
    required ReadingTimerPhase phase,
    DateTime? runningSince,
    List<ReadingInterval>? intervals,
    bool clearTarget = false,
  }) => ReadingTimer(
    id: id,
    bookId: bookId,
    bookTitle: bookTitle,
    startedAt: startedAt,
    deviceId: deviceId,
    shelfIds: shelfIds,
    startPage: startPage,
    targetSeconds: clearTarget ? null : targetSeconds,
    phase: phase,
    runningSince: runningSince,
    intervals: intervals ?? this.intervals,
    revision: revision + 1,
    versionToken: const Uuid().v4(),
  );

  List<ReadingActivity> activities(DateTime now, {int pages = 0}) {
    final stopped = stop(now, finish: true);

    return [
      for (final (index, interval) in stopped.intervals.indexed)
        ReadingActivity(
          id: const Uuid().v5(id, '$index'),
          sessionId: id,
          bookId: bookId,
          bookTitle: bookTitle,
          startTime: interval.start,
          endTime: interval.end,
          createdAt: now.isBefore(interval.end) ? interval.end : now.toUtc(),
          deviceId: deviceId,
          deviceType: 'physical_timer',
          shelfIds: shelfIds,
          pages: index == stopped.intervals.length - 1 ? pages : 0,
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'book_id': bookId,
    'book_title': bookTitle,
    'started_at': startedAt.toIso8601String(),
    'device_id': deviceId,
    'shelf_ids': shelfIds,
    'start_page': startPage,
    'target_seconds': targetSeconds,
    'phase': phase.name,
    'running_since': runningSince?.toIso8601String(),
    'intervals': intervals.map((interval) => interval.toJson()).toList(),
    'revision': revision,
    'version': version,
  };

  factory ReadingTimer.fromJson(Map<String, dynamic> json) => ReadingTimer(
    id: json['id'] as String,
    bookId: json['book_id'] as String,
    bookTitle: json['book_title'] as String,
    startedAt: DateTime.parse(json['started_at'] as String),
    deviceId: json['device_id'] as String,
    shelfIds: List<String>.from(json['shelf_ids'] as List),
    startPage: json['start_page'] as int,
    targetSeconds: json['target_seconds'] as int?,
    phase: ReadingTimerPhase.values.byName(json['phase'] as String),
    runningSince: json['running_since'] == null ? null : DateTime.parse(json['running_since'] as String),
    intervals: (json['intervals'] as List)
        .map((value) => ReadingInterval.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList(),
    revision: json['revision'] as int,
    versionToken: json['version'] as String?,
  );
}
