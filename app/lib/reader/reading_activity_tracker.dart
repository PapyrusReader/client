import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

/// Checkpoints are durable intervals; failures retry the same IDs, never increments.
class ReadingActivityTracker {
  ReadingActivityTracker({
    required this.repository,
    required this.book,
    required List<String> shelfIds,
    required this.deviceId,
    required this.onError,
    DateTime Function()? now,
    this.checkpointInterval = const Duration(seconds: 10),
    this.exposureThreshold = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now,
       shelfIds = List.of(shelfIds) {
    _timer = Timer.periodic(checkpointInterval, (_) => unawaited(flush()));
  }
  final TrackingRepository repository;
  final Book book;
  List<String> shelfIds;
  final String deviceId;
  final void Function(Object) onError;
  final DateTime Function() _now;
  final Duration checkpointInterval;
  final Duration exposureThreshold;
  final String sessionId = const Uuid().v4();
  Timer? _timer;
  ReaderActivityEvent? _event;
  ReaderLocator? _locator;
  bool _foreground = true;
  bool _disposed = false;
  DateTime? _started;
  DateTime? _exposedSince;
  String _coverageKey = '';
  final List<ReadingActivity> _pending = [];
  Map<String, dynamic>? _pendingPatch;
  Future<void> _writes = Future.value();
  bool get _active =>
      !_disposed && _foreground && _event?.ready == true && _event?.visible == true && repository.isCurrent;

  void onActivity(ReaderActivityEvent event) {
    final wasActive = _active;
    final now = _now().toUtc();
    final key = jsonEncode(event.coverage.map((c) => [c.key, c.start, c.end, c.chapterCount]).toList());
    final changed = key != _coverageKey;
    if (changed || wasActive && (!event.ready || !event.visible)) _capture(now);
    _event = event;
    _coverageKey = key;
    if (changed) _exposedSince = null;
    if (!_active) {
      _started = null;
      _exposedSince = null;
    } else {
      _started ??= now;
      _exposedSince ??= now;
    }
    if (event.locator != null) updateLocator(event.locator!);
    if (changed || wasActive != _active) unawaited(_drain());
  }

  void updateScope(List<String> ids) {
    if (_disposed || ids.length == shelfIds.length && ids.every(shelfIds.contains)) return;
    _capture(_now().toUtc());
    shelfIds = List.of(ids);
    unawaited(_drain());
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _capture(_now().toUtc());
    _foreground = foreground;
    _started = _active ? _now().toUtc() : null;
    _exposedSince = _started;
    unawaited(_drain());
  }

  void updateLocator(ReaderLocator locator) {
    _locator = locator;
    final position = switch (locator) {
      EpubReaderLocator(:final totalProgression) => totalProgression,
      PdfReaderLocator(:final totalProgression) => totalProgression,
    };
    _pendingPatch = {
      'reader_locator': locator.toJson(),
      'current_position': position,
      'last_read_at': _now().toUtc().toIso8601String(),
      if (locator is PdfReaderLocator) 'current_page': locator.pageIndex + 1,
      if (locator is EpubReaderLocator) 'current_cfi': locator.cfi,
    };
  }

  void _capture(DateTime now) {
    final start = _started;
    if (start == null || !_active || !now.isAfter(start)) return;
    final coverage = <PageCoverage>[];
    if (_exposedSince != null && now.difference(_exposedSince!) >= exposureThreshold) {
      for (final extent in _event!.coverage) {
        if (extent.end <= extent.start) continue;
        final chapterCount = extent.chapterCount;
        final pageCount = book.pageCount;
        if (chapterCount != null && (pageCount == null || pageCount <= 0)) continue;
        coverage.add(
          PageCoverage(
            key: '${book.id}:${extent.key}',
            start: extent.start,
            end: extent.end,
            pagesPerUnit: chapterCount == null ? 1 : pageCount! / chapterCount,
            estimated: chapterCount != null,
          ),
        );
      }
    }
    _pending.add(
      ReadingActivity(
        id: const Uuid().v4(),
        bookId: book.id,
        bookTitle: book.title,
        startTime: start,
        endTime: now,
        createdAt: now,
        source: 'reader',
        sessionId: sessionId,
        deviceId: deviceId,
        shelfIds: shelfIds,
        coverage: coverage,
      ),
    );
    _started = now;
    final locator = _locator;
    if (locator != null) updateLocator(locator);
  }

  Future<void> flush() {
    _capture(_now().toUtc());
    return _drain();
  }

  Future<void> _drain() {
    final operation = _writes.then((_) async {
      if (!repository.isCurrent || _pending.isEmpty && _pendingPatch == null) return;
      final batch = List<ReadingActivity>.from(_pending);
      final patch = _pendingPatch;
      try {
        await repository.commitTracking(
          activities: batch,
          readerBookId: patch == null ? null : book.id,
          readerPatch: patch,
        );
        _pending.removeWhere((activity) => batch.any((saved) => saved.id == activity.id));
        if (identical(_pendingPatch, patch)) _pendingPatch = null;
      } catch (error) {
        onError(error);
      }
    });
    _writes = operation;
    return operation;
  }

  Future<void> close() async {
    _timer?.cancel();
    _capture(_now().toUtc());
    _disposed = true;
    await _drain();
    if (repository.isCurrent && (_pending.isNotEmpty || _pendingPatch != null)) {
      _disposed = false;
      _started = _active ? _now().toUtc() : null;
      _timer = Timer.periodic(checkpointInterval, (_) => unawaited(flush()));
      throw StateError('Reading activity is still pending a local write.');
    }
  }
}
