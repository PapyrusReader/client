import 'package:papyrus/models/reading_session.dart';

/// Stable document coverage, independent of the current screen's pagination.
class PageCoverage {
  const PageCoverage({
    required this.key,
    required this.start,
    required this.end,
    required this.pagesPerUnit,
    this.estimated = false,
  });
  final String key;
  final double start;
  final double end;
  final double pagesPerUnit;
  final bool estimated;
  Map<String, dynamic> toJson() => {
    'key': key,
    'start': start,
    'end': end,
    'pages_per_unit': pagesPerUnit,
    'estimated': estimated,
  };
  factory PageCoverage.fromJson(Map<String, dynamic> json) => PageCoverage(
    key: json['key'] as String,
    start: (json['start'] as num).toDouble(),
    end: (json['end'] as num).toDouble(),
    pagesPerUnit: (json['pages_per_unit'] as num).toDouble(),
    estimated: json['estimated'] == true,
  );
}

/// Append-only reading ledger. Corrections reverse a record and add a replacement.
class ReadingActivity {
  const ReadingActivity({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    this.sessionId,
    this.recordedSeconds,
    this.constituentIds = const [],
    this.source = 'manual',
    this.kind = 'reading',
    this.deviceId = 'manual',
    this.shelfIds = const [],
    this.pages = 0,
    this.coverage = const [],
    this.note,
    this.correctionOf,
  });
  final String? sessionId;
  final int? recordedSeconds;
  final List<String> constituentIds;
  final String id;
  final String bookId;
  final String bookTitle;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime createdAt;
  final String source;
  final String kind;
  final String deviceId;
  final List<String> shelfIds;
  final int pages;
  final List<PageCoverage> coverage;
  final String? note;
  final String? correctionOf;
  bool get isEstimated => coverage.any((value) => value.estimated);
  int get seconds => recordedSeconds ?? endTime.difference(startTime).inSeconds;
  ReadingSession get session => ReadingSession(
    id: id,
    bookId: bookId,
    startTime: startTime,
    endTime: endTime,
    startPosition: 0,
    pagesRead: pages,
    deviceType: source,
    deviceName: deviceId,
    createdAt: createdAt,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'book_id': bookId,
    'book_title': bookTitle,
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'source': source,
    'kind': kind,
    'device_id': deviceId,
    'shelf_ids': shelfIds,
    'pages': pages,
    'coverage': coverage.map((value) => value.toJson()).toList(),
    'note': note,
    'correction_of': correctionOf,
  };
  factory ReadingActivity.fromJson(Map<String, dynamic> json) => ReadingActivity(
    id: json['id'] as String,
    sessionId: json['session_id'] as String?,
    bookId: json['book_id'] as String,
    bookTitle: json['book_title'] as String,
    startTime: DateTime.parse(json['start_time'] as String).toUtc(),
    endTime: DateTime.parse(json['end_time'] as String).toUtc(),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    source: json['source'] as String? ?? 'manual',
    kind: json['kind'] as String? ?? 'reading',
    deviceId: json['device_id'] as String? ?? 'manual',
    shelfIds: List<String>.from(json['shelf_ids'] as List? ?? []),
    pages: json['pages'] as int? ?? 0,
    coverage: (json['coverage'] as List? ?? [])
        .map((value) => PageCoverage.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList(),
    note: json['note'] as String?,
    correctionOf: json['correction_of'] as String?,
  );
}

List<ReadingActivity> effectiveActivities(Iterable<ReadingActivity> activities) {
  final unique = {for (final value in activities) value.id: value};
  final reversed = unique.values.where((value) => value.kind == 'reversal').map((value) => value.correctionOf).toSet();
  return unique.values.where((value) => value.kind != 'reversal' && !reversed.contains(value.id)).toList();
}

/// Checkpoints remain immutable records; presentation groups a reader opening.
List<ReadingActivity> groupReadingActivities(Iterable<ReadingActivity> ledger) {
  final groups = <String, List<ReadingActivity>>{};
  for (final entry in ledger) {
    final key = entry.source == 'reader' && entry.kind == 'reading' && entry.sessionId != null
        ? '${entry.bookId}:${entry.sessionId}'
        : entry.id;
    groups.putIfAbsent(key, () => []).add(entry);
  }
  final result = groups.values.map((entries) {
    entries.sort((a, b) => a.startTime.compareTo(b.startTime));
    if (entries.length == 1) return entries.first;
    final first = entries.first;
    final ends = entries.map((a) => a.endTime).toList()..sort();
    var cursor = first.startTime;
    var end = first.endTime;
    var seconds = 0;
    for (final entry in entries.skip(1)) {
      if (entry.startTime.isAfter(end)) {
        seconds += end.difference(cursor).inSeconds;
        cursor = entry.startTime;
      }
      if (entry.endTime.isAfter(end)) end = entry.endTime;
    }
    seconds += end.difference(cursor).inSeconds;
    return ReadingActivity(
      id: first.id,
      sessionId: first.sessionId,
      bookId: first.bookId,
      bookTitle: first.bookTitle,
      startTime: first.startTime,
      endTime: ends.last,
      createdAt: first.createdAt,
      source: first.source,
      deviceId: first.deviceId,
      shelfIds: first.shelfIds,
      recordedSeconds: seconds,
      coverage: entries.expand((a) => a.coverage).toList(),
      constituentIds: entries.map((a) => a.id).toList(),
    );
  }).toList()..sort((a, b) => b.endTime.compareTo(a.endTime));
  return result;
}
