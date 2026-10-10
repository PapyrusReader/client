import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// A separate validation entrypoint, packaged with the production native bundle.
// It is never selected by the release workflow's production Flutter build.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = Platform.environment['PAPYRUS_SMOKE_REPORT'];

  if (report == null) {
    throw StateError('PAPYRUS_SMOKE_REPORT must identify a disposable test report');
  }

  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      await File(report).writeAsString(
        jsonEncode({
          'passed': passed,
          'platform': Platform.operatingSystem,
          'results': binding.results.map((key, value) => MapEntry(key, value.toString())),
        }),
      );
      exit(passed ? 0 : 1);
    }),
  );

  testWidgets(
    'packaged offline import, EPUB/PDF rendering, resume and profile isolation',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('papyrus-package-smoke-');
      final importer = BookImportService();
      final importedIds = <String>[];
      var database = createDatabase(root);

      try {
        await database.activateGuest();
        final fixtures = {'epub': createEpub(), 'pdf': await createPdf()};

        for (final fixture in fixtures.entries) {
          final imported = await importer.importBook(fixture.value, 'Package smoke.${fixture.key}');
          importedIds.add(imported.bookId);
          expect(await importer.getBookFile(imported.bookId), fixture.value);
          final format = fixture.key == 'epub' ? BookFormat.epub : BookFormat.pdf;
          final book = Book(
            id: imported.bookId,
            title: imported.title,
            author: imported.author,
            addedAt: DateTime.now().toUtc(),
            fileFormat: format,
            pageCount: imported.pageCount,
          );
          await database.upsert(book);
          final document = ReaderDocument(
            id: book.id,
            format: ReaderBookAdapter.formatFor(format)!,
            loadBytes: () async => (await importer.getBookFile(book.id))!,
          );
          var controller = ReaderController(registry: ReaderEngineRegistry.defaults());
          await tester.pumpWidget(
            MaterialApp(
              home: PapyrusReader(document: document, controller: controller),
            ),
          );
          await waitForContent(tester, controller);
          final first = controller.snapshot.locator!.toJson();
          await tester.tap(find.byTooltip('Next'));
          await waitForContent(tester, controller);
          expect(controller.snapshot.locator!.toJson(), isNot(first), reason: '${fixture.key} must advance');
          final saved = controller.snapshot.locator!;
          await database.upsert(ReaderBookAdapter.applyLocator(book, saved, now: DateTime.now().toUtc()));
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();

          // Close the actual SQLite connection before checking persisted resume.
          await database.close();
          database = createDatabase(root);
          await database.activateGuest();
          final restored = ReaderBookAdapter.restoreLocator((await database.getById(book.id))!);
          expect(restored!.toJson(), saved.toJson());
          controller = ReaderController(registry: ReaderEngineRegistry.defaults());
          await tester.pumpWidget(
            MaterialApp(
              home: PapyrusReader(document: document, controller: controller, initialLocator: restored),
            ),
          );
          await waitForContent(tester, controller);
          expect(controller.snapshot.locator!.toJson(), saved.toJson());
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }

        final guestBook = (await database.getById(importedIds.first))!;

        for (final profile in [('server-a', 'user-a'), ('server-a', 'user-b'), ('server-b', 'user-a')]) {
          await database.activateAuthenticated(profile.$2, profileKey: profile.$1);
          expect(await database.getById(guestBook.id), isNull);
          await database.upsert(guestBook.copyWith(title: '${profile.$1}/${profile.$2}'));
        }

        for (final profile in [('server-a', 'user-a'), ('server-a', 'user-b'), ('server-b', 'user-a')]) {
          await database.activateAuthenticated(profile.$2, profileKey: profile.$1);
          expect((await database.getById(guestBook.id))!.title, '${profile.$1}/${profile.$2}');
        }

        await database.activateGuest();
        expect((await database.getById(guestBook.id))!.title, guestBook.title);
        final scopeA = MediaStorageScope(
          profileKey: 'package-test-a',
          userId: root.path.split(Platform.pathSeparator).last,
        );
        final scopeB = MediaStorageScope(profileKey: 'package-test-b', userId: scopeA.userId);
        await importer.storeCoverFile(scopeA, guestBook.id, Uint8List.fromList([1, 2, 3]));

        try {
          expect(await importer.getCoverFile(scopeB, guestBook.id), isNull);
          expect(await importer.getCoverFile(scopeA, guestBook.id), Uint8List.fromList([1, 2, 3]));
        } finally {
          await importer.deleteCoverFile(scopeA, guestBook.id);
        }

        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await database.close();

        for (final id in importedIds) {
          await importer.deleteBookFile(id);
        }

        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

PapyrusPowerSyncService createDatabase(Directory root) => PapyrusPowerSyncService(
  connectorFactory: OfflineConnector.new,
  connectAuthenticated: false,
  pathResolver: (mode, profile, user) async => '${root.path}/${mode.name}-${profile ?? 'guest'}-${user ?? 'guest'}.db',
);

class OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => throw StateError('Smoke test must remain offline');

  @override
  Future<void> uploadData(PowerSyncDatabase database) async => throw StateError('Smoke test must remain offline');
}

Future<void> waitForContent(WidgetTester tester, ReaderController controller) async {
  for (var frame = 0; frame < 300; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.snapshot.error, isNull);

    if (controller.snapshot.contentReady && controller.snapshot.locator != null) {
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }

  fail('Packaged reader never rendered content');
}

Uint8List createEpub() {
  final archive = Archive();

  void add(String name, String contents) {
    final bytes = utf8.encode(contents);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''');
  add('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">package-smoke</dc:identifier>
<dc:title>Offline packaging book</dc:title><dc:creator>Papyrus</dc:creator><dc:language>en</dc:language></metadata>
<manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
<spine toc="toc"><itemref idref="chapter"/></spine></package>''');
  add('toc.ncx', '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="package-smoke"/></head><docTitle><text>Offline book</text></docTitle>
<navMap><navPoint id="chapter" playOrder="1"><navLabel><text>Chapter</text></navLabel>
<content src="chapter.xhtml"/></navPoint></navMap></ncx>''');
  add('chapter.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head><body>
${List.generate(120, (index) => '<p>Paragraph $index. Papyrus reads this book offline and preserves the reading position after reopening.</p>').join()}
</body></html>''');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<Uint8List> createPdf() async {
  final document = PdfDocument();

  try {
    for (var page = 1; page <= 3; page++) {
      document.pages.add().graphics.drawString(
        'Papyrus offline PDF page $page',
        PdfStandardFont(PdfFontFamily.helvetica, 20),
      );
    }

    document.documentInformation.title = 'Offline PDF';
    return Uint8List.fromList(await document.save());
  } finally {
    document.dispose();
  }
}
