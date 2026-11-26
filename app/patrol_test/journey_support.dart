import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/main.dart' as app;
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:patrol/patrol.dart';
import 'package:provider/provider.dart';

extension LibraryJourney on PatrolIntegrationTester {
  BuildContext get screen => tester.element(find.byType(Scaffold).last);
  GoRouter get router => GoRouter.of(screen);

  DataStore get store => screen.read<DataStore>();

  Future<void> startGuest() async {
    await app.main();
    await tester.pump();
    await this('Continue offline').tap();
    await this(find.byType(LibraryPage)).waitUntilExists();
    await store.waitUntilLoaded();
  }

  Future<void> reopenGuest() async {
    final closed = screen.read<PapyrusPowerSyncService>().syncStates.drain<void>();
    await tester.pumpWidget(const SizedBox.shrink());
    await closed.timeout(const Duration(seconds: 15));
    await app.main();
    await tester.pump();
    await this(find.byType(LibraryPage)).waitUntilExists();
    await store.waitUntilLoaded();
  }

  Future<void> visit(String path) async {
    router.go(path);
    await tester.pumpAndSettle();
  }

  Future<Book> seedBook(String title, {BookFormat? format}) async {
    final id = title.toLowerCase().replaceAll(' ', '-');

    if (format != null) {
      final encoded = format == BookFormat.epub
          ? const String.fromEnvironment('JOURNEY_EPUB')
          : const String.fromEnvironment('JOURNEY_PDF');
      expect(encoded, isNotEmpty, reason: 'Run with tools/mobile_journey.sh to supply the fixture.');
      await BookImportService().storeBookFile(id, format.name, base64Decode(encoded));
    }

    final book = Book(id: id, title: title, author: 'Journey fixture', fileFormat: format, addedAt: DateTime.now());
    await store.addBookAndWait(book);
    return book;
  }

  Future<void> fill(String label, String value) async {
    final field = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == label);
    await this(field).waitUntilExists();
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }
}
