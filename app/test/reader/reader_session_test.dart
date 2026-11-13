import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/reader/reader_session.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final format in BookFormat.values) {
    ReaderLocator location(double progress) {
      if ([BookFormat.epub, BookFormat.mobi, BookFormat.azw3, BookFormat.txt].contains(format)) {
        return EpubReaderLocator(
          spineIndex: 0,
          textOffset: (progress * 1000).round(),
          localProgression: progress,
          totalProgression: progress,
        );
      }
      return PdfReaderLocator(pageIndex: (progress * 10).round(), pageOffset: 0, totalProgression: progress);
    }

    ReaderActivityEvent activity(ReaderLocator locator, ReaderNavigationCause cause) =>
        ReaderActivityEvent(ready: true, visible: true, cause: cause, locator: locator);

    test('$format annotation visits preserve resume on close and reflow', () async {
      final saved = <Book>[];
      final session = ReaderSession(
        book: buildTestBook(fileFormat: format, currentPosition: .8),
        saveBook: saved.add,
        preserveLocation: true,
      );
      for (final cause in [
        ReaderNavigationCause.restore,
        ReaderNavigationCause.viewport,
        ReaderNavigationCause.reflow,
      ]) {
        final locator = location(cause == ReaderNavigationCause.reflow ? .21 : .2);
        session.updateLocator(locator);
        session.onActivity(activity(locator, cause));
      }
      await session.flush();
      session.dispose();
      expect(saved, isEmpty);
    });

    for (final scroll in [false, true]) {
      test('$format continues saving after ${scroll ? 'scrolling' : 'turning'} from a visit', () async {
        final saved = <Book>[];
        final session = ReaderSession(
          book: buildTestBook(fileFormat: format, currentPosition: .8),
          saveBook: saved.add,
          preserveLocation: true,
        );
        session.updateLocator(location(.2));
        session.onActivity(activity(location(.2), ReaderNavigationCause.restore));
        // A failed/no-op page turn must not adopt the inspected location.
        session.onActivity(activity(location(.2), ReaderNavigationCause.turn));
        expect(session.isLocationVisit, isTrue);
        if (scroll) session.recordScrollIntent();
        session.updateLocator(location(.3));
        session.onActivity(
          activity(location(.3), scroll ? ReaderNavigationCause.viewport : ReaderNavigationCause.turn),
        );
        await session.flush();
        expect(session.isLocationVisit, isFalse);
        expect(saved.single.currentPosition, .3);
        session.updateLocator(location(.4));
        await session.flush();
        expect(saved.last.currentPosition, .4);
        session.beginLocationVisit();
        session.updateLocator(location(.1));
        session.onActivity(activity(location(.1), ReaderNavigationCause.jump));
        session.dispose();
        expect(saved.last.currentPosition, .4);
        expect(saved, hasLength(2));
      });
    }
  }

  test('coalesces rapid locator changes into the latest saved book', () async {
    final saved = <Book>[];

    final session = ReaderSession(
      book: buildTestBook(fileFormat: BookFormat.pdf),
      saveBook: saved.add,
      debounceDuration: Duration.zero,
      now: () => DateTime.utc(2026, 7, 27),
    );

    session.updateLocator(PdfReaderLocator(pageIndex: 1, pageOffset: 0, totalProgression: 0.1));
    session.updateLocator(PdfReaderLocator(pageIndex: 4, pageOffset: 0, totalProgression: 0.4));
    await Future<void>.delayed(Duration.zero);
    expect(saved, hasLength(1));
    expect(saved.single.currentPage, 5);
    expect(saved.single.currentPosition, 0.4);
    session.dispose();
  });

  test('dispose flushes the final pending locator', () {
    final saved = <Book>[];

    final session = ReaderSession(
      book: buildTestBook(fileFormat: BookFormat.epub),
      saveBook: saved.add,
      debounceDuration: const Duration(days: 1),
      now: () => DateTime.utc(2026, 7, 27),
    );

    session.updateLocator(
      EpubReaderLocator(spineIndex: 1, localProgression: 0.5, totalProgression: 0.25),
    );

    session.dispose();
    expect(saved, hasLength(1));
    expect(saved.single.currentPosition, 0.25);
  });
}
