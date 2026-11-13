import 'dart:async';
import 'package:papyrus/reader/reading_activity_tracker.dart';

import 'package:papyrus/models/book.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

typedef BookSaveCallback = void Function(Book book);
typedef ReaderClock = DateTime Function();

final class ReaderSession {
  ReaderSession({
    required Book book,
    required BookSaveCallback saveBook,
    this.tracker,
    bool preserveLocation = false,
    this.debounceDuration = const Duration(milliseconds: 500),
    ReaderClock? now,
  }) : _book = book,
       _locationVisit = preserveLocation,
       _saveBook = saveBook,
       _now = now ?? DateTime.now;

  final ReadingActivityTracker? tracker;
  final BookSaveCallback _saveBook;
  final ReaderClock _now;
  final Duration debounceDuration;

  Book _book;
  ReaderLocator? _pendingLocator;
  Timer? _timer;
  bool _disposed = false;
  bool _locationVisit;
  ReaderLocator? _observedLocator;
  bool _scrollPending = false;

  /// Saved-location visits do not replace resume data until reading continues.
  bool get isLocationVisit => _locationVisit;

  void beginLocationVisit() {
    _locationVisit = true;
    _scrollPending = false;
  }

  void recordScrollIntent() {
    _scrollPending = true;
  }

  void clearScrollIntent() {
    _scrollPending = false;
  }

  void onActivity(ReaderActivityEvent event) {
    if (_disposed) {
      return;
    }

    final locator = event.locator;

    final continuedReading =
        event.cause == ReaderNavigationCause.turn || event.cause == ReaderNavigationCause.viewport && _scrollPending;

    if (_locationVisit &&
        continuedReading &&
        locator != null &&
        _observedLocator != null &&
        locator != _observedLocator) {
      _locationVisit = false;
      updateLocator(locator);
    }

    if (locator != null && locator != _observedLocator || event.cause != ReaderNavigationCause.viewport) {
      _scrollPending = false;
    }

    if (locator != null) {
      _observedLocator = locator;
    }

    tracker?.onActivity(event, savePosition: !_locationVisit);
  }

  void updateLocator(ReaderLocator locator) {
    if (_disposed || _locationVisit) {
      return;
    }

    _pendingLocator = locator;
    tracker?.updateLocator(locator);
    _timer?.cancel();
    _timer = Timer(debounceDuration, () => unawaited(flush()));
  }

  Future<void> flush() async {
    final locator = _pendingLocator;

    if (locator == null) {
      await tracker?.flush();
      return;
    }

    _timer?.cancel();
    _timer = null;
    _pendingLocator = null;

    if (tracker != null) {
      await tracker!.flush();
      return;
    }

    _book = ReaderBookAdapter.applyLocator(_book, locator, now: _now());
    _saveBook(_book);
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    unawaited(flush());
    unawaited(tracker?.close().catchError((Object error) => tracker!.onError(error)));
    _disposed = true;
  }
}
