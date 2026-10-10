import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

import 'desktop_package_fixtures.dart';
import 'desktop_package_persistence.dart';

// A separate validation entrypoint, packaged with the production native bundle.
// It is never selected by the release workflow's production Flutter build.
Future<void> main() async {
  if (Platform.environment.containsKey('PAPYRUS_PERSISTENCE_PHASE')) {
    await runPersistenceProbe();
    return;
  }

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
