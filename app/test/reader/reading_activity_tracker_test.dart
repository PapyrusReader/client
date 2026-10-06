import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/goal_period_record.dart';
import 'package:papyrus/reader/reading_activity_tracker.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

class RecordingRepository implements TrackingRepository {
  @override
  bool isCurrent = true;
  int failures = 0;
  final records = <String, ReadingActivity>{};
  final attemptedIds = <List<String>>[];
  final patches = <Map<String, dynamic>>[];
  @override
  Future<void> commitTracking({
    List<ReadingGoal> goals = const [],
    List<ReadingActivity> activities = const [],
    List<GoalPeriodRecord> periods = const [],
    String? deleteGoalId,
    Book? book,
    Book? previousBook,
    String? readerBookId,
    Map<String, dynamic>? readerPatch,
  }) async {
    attemptedIds.add(activities.map((a) => a.id).toList());
    if (failures > 0) {
      failures--;
      throw StateError('Disk unavailable');
    }
    for (final activity in activities) {
      records[activity.id] = activity;
    }
    if (readerPatch != null) patches.add(readerPatch);
  }
}

void main() {
  final start = DateTime.utc(2026, 10, 6, 12);
  const pages = [
    ReaderContentCoverage(key: 'pdf:0', start: 0, end: 1, pdfPageIndex: 0),
    ReaderContentCoverage(key: 'pdf:1', start: 0, end: 1, pdfPageIndex: 1),
  ];
  ReaderActivityEvent event({bool ready = true, bool visible = true, List<ReaderContentCoverage> coverage = pages}) =>
      ReaderActivityEvent(ready: ready, visible: visible, cause: ReaderNavigationCause.viewport, coverage: coverage);
  test('ready foreground time includes no inactivity timeout; panels and lifecycle pause', () async {
    var now = start;
    final repository = RecordingRepository();
    final tracker = ReadingActivityTracker(
      repository: repository,
      book: Book(id: 'book', title: 'Book', author: '', addedAt: start),
      shelfIds: ['shelf'],
      deviceId: 'one',
      onError: (_) {},
      now: () => now,
      checkpointInterval: const Duration(days: 1),
    );
    tracker.onActivity(event(ready: false));
    now = now.add(const Duration(minutes: 2));
    await tracker.flush();
    expect(repository.records, isEmpty);
    tracker.onActivity(event());
    now = now.add(const Duration(minutes: 20));
    tracker.setForeground(false);
    await tracker.flush();
    expect(repository.records.values.single.seconds, 1200);
    expect(repository.records.values.single.coverage.length, 2);
    tracker.updateScope(['new shelf']);
    now = now.add(const Duration(minutes: 4));
    tracker.setForeground(true);
    now = now.add(const Duration(seconds: 4));
    tracker.onActivity(event(visible: false));
    now = now.add(const Duration(minutes: 3));
    await tracker.close();
    expect(repository.records.values.fold<int>(0, (n, a) => n + a.seconds), 1204);
    expect(repository.records.values.last.coverage, isEmpty);
    expect(repository.records.values.first.shelfIds, ['shelf']);
    expect(repository.records.values.last.shelfIds, ['new shelf']);
  });
  test('jumps only credit actual exposed pages after ten seconds', () async {
    var now = start;
    final repository = RecordingRepository();
    final tracker = ReadingActivityTracker(
      repository: repository,
      book: Book(id: 'book', title: 'Book', author: '', addedAt: start),
      shelfIds: [],
      deviceId: 'one',
      onError: (_) {},
      now: () => now,
      checkpointInterval: const Duration(days: 1),
    );
    tracker.onActivity(event());
    now = now.add(const Duration(seconds: 9));
    await tracker.flush();
    expect(repository.records.values.single.coverage, isEmpty);
    tracker.onActivity(
      event(coverage: const [ReaderContentCoverage(key: 'pdf:99', start: 0, end: 1, pdfPageIndex: 99)]),
    );
    now = now.add(const Duration(seconds: 10));
    await tracker.close();
    expect(repository.records.values.expand((a) => a.coverage).map((c) => c.key).toSet(), {'book:pdf:99'});
  });
  test('write retries reuse UUIDs and captured profiles cannot write into another library', () async {
    var now = start;
    final repository = RecordingRepository()..failures = 1;
    final errors = <Object>[];
    final tracker = ReadingActivityTracker(
      repository: repository,
      book: Book(id: 'book', title: 'Book', author: '', addedAt: start),
      shelfIds: [],
      deviceId: 'one',
      onError: errors.add,
      now: () => now,
      checkpointInterval: const Duration(days: 1),
    );
    tracker.onActivity(event());
    now = now.add(const Duration(seconds: 10));
    await tracker.flush();
    expect(errors.length, 1);
    await tracker.flush();
    expect(repository.attemptedIds.first, repository.attemptedIds.last);
    expect(repository.records.length, 1);
    repository.isCurrent = false;
    now = now.add(const Duration(seconds: 20));
    await tracker.close();
    expect(repository.records.length, 1);
  });
  test('EPUB metadata calibration is estimated; no metadata still records time', () async {
    for (final count in [null, 200]) {
      var now = start;
      final repository = RecordingRepository();
      final tracker = ReadingActivityTracker(
        repository: repository,
        book: Book(id: 'book', title: 'Book', author: '', addedAt: start, pageCount: count),
        shelfIds: [],
        deviceId: 'one',
        onError: (_) {},
        now: () => now,
        checkpointInterval: const Duration(days: 1),
      );
      tracker.onActivity(
        event(coverage: const [ReaderContentCoverage(key: 'epub:0:1000', start: .1, end: .3, chapterCount: 10)]),
      );
      now = now.add(const Duration(seconds: 10));
      await tracker.close();
      final activity = repository.records.values.single;
      expect(activity.seconds, 10);
      expect(activity.coverage.length, count == null ? 0 : 1);
      if (count != null) {
        expect(activity.coverage.single.pagesPerUnit, 20);
        expect(activity.isEstimated, isTrue);
      }
    }
  });
}
