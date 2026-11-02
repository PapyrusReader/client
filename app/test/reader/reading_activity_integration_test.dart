import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/reader/reading_activity_tracker.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:papyrus_reader/src/engine/epub/worker/epub_processor.dart';
import 'package:papyrus_reader/src/engine/epub/worker/epub_worker.dart';

import 'reading_activity_tracker_test.dart' show RecordingRepository;

void main() {
  testWidgets('actual reader coverage credits consecutive EPUB pages without collapsing a chapter', (tester) async {
    var now = DateTime.utc(2026, 11, 2, 12);
    final repository = RecordingRepository();
    final tracker = ReadingActivityTracker(
      repository: repository,
      book: Book(id: 'book', title: 'Book', author: '', addedAt: now, pageCount: 200),
      shelfIds: [],
      deviceId: 'one',
      onError: (_) {},
      now: () => now,
      checkpointInterval: const Duration(days: 1),
    );
    final engine = EpubReaderEngine(workerFactory: () async => _InProcessWorker());
    addTearDown(engine.dispose);
    await engine.load(
      ReaderDocument(id: 'book', format: ReaderFormat.epub, loadBytes: () async => _book()),
      preferences: const ReaderPreferences(columnMode: ReaderColumnMode.single, pageTurnAnimation: false),
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: engine.buildViewport)));
    await tester.pumpAndSettle();

    final first = engine.snapshot.coverage.single;
    tracker.onActivity(_event(engine));
    now = now.add(const Duration(seconds: 10));
    await tracker.flush();
    final firstPages = repository.records.values.single.coverage.single;
    final firstTotal = (firstPages.end - firstPages.start) * firstPages.pagesPerUnit;
    var turned = false;
    final turn = engine.goNext().then((_) => turned = true);

    for (var frame = 0; !turned && frame < 100; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(turned, isTrue);
    await turn;
    await tester.pumpAndSettle();
    final second = engine.snapshot.coverage.single;
    expect(second.start, greaterThan(first.start));
    tracker.onActivity(_event(engine));
    now = now.add(const Duration(seconds: 10));
    await tracker.close();
    final coverage = repository.records.values.expand((activity) => activity.coverage).toList();
    expect(coverage, hasLength(2));

    if (first.chapterCount != null) {
      // The Git-pinned reader emits normalized chapter extents.
      expect(coverage.map((extent) => (extent.start, extent.end)), [
        (first.start, first.end),
        (second.start, second.end),
      ]);
      expect(coverage.every((extent) => extent.estimated), isTrue);
      final total = coverage.fold<double>(0, (sum, extent) => sum + (extent.end - extent.start) * extent.pagesPerUnit);
      expect(total, greaterThan(firstTotal));
    } else {
      expect(coverage.map((extent) => extent.key).toSet(), hasLength(2));
      expect(coverage.every((extent) => !extent.estimated && extent.end - extent.start == 1), isTrue);
    }
  });
}

ReaderActivityEvent _event(EpubReaderEngine engine) => ReaderActivityEvent(
  ready: engine.snapshot.contentReady,
  visible: true,
  cause: ReaderNavigationCause.viewport,
  coverage: engine.snapshot.coverage,
);

Uint8List _book() {
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'content.opf':
        '<package version="2.0" unique-identifier="book-id" xmlns="http://www.idpf.org/2007/opf">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">book</dc:identifier>'
        '<dc:title>Book</dc:title><dc:language>en</dc:language></metadata><manifest>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine toc="ncx"><itemref idref="chapter"/></spine></package>',
    'toc.ncx':
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<head><meta name="dtb:uid" content="book"/></head><docTitle><text>Book</text></docTitle><navMap/></ncx>',
    'chapter.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '${List.filled(200, '<p>Reading across pages must preserve the amount of content actually viewed.</p>').join()}'
        '</body></html>',
  };
  final archive = Archive();

  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _InProcessWorker implements EpubWorker {
  final _processor = EpubProcessor();

  @override
  Future<Map<String, Object?>> request(String command, Object? argument) async {
    final response = await processEpubMessage(_processor, {'id': 1, 'command': command, 'argument': argument});

    if (response['error'] != null) {
      throw StateError('${response['error']}: ${response['message']}');
    }

    return Map<String, Object?>.from(response['result'] as Map);
  }

  @override
  void dispose() {}
}
