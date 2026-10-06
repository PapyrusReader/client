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
    this.debounceDuration = const Duration(milliseconds: 500),
    ReaderClock? now,
  }) : _book = book,
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

  void updateLocator(ReaderLocator locator) {
    if (_disposed) return;

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
    if (_disposed) return;

    unawaited(flush());
    unawaited(tracker?.close().catchError((Object error) => tracker!.onError(error)));
    _disposed = true;
  }
}
