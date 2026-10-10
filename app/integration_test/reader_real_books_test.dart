import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';

import 'support/tracking_app.dart';

// Opt-in device test. Serve reader.epub (Alice), pride.epub, and reader.pdf
// locally. READER_INCLUDE_SQL additionally requires local-only sql.epub.
const runReaderValidation = bool.fromEnvironment('RUN_READER_VALIDATION');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real books retain progress and content through client reader interactions',
    (tester) async {
      const origin = String.fromEnvironment('TRACKING_FIXTURE_ORIGIN', defaultValue: 'http://127.0.0.1:8755');
      final timings = <String, int>{};

      for (final book in ['alice', 'pride', if (const bool.fromEnvironment('READER_INCLUDE_SQL')) 'sql']) {
        final app = TrackingValidationApp();
        await app.initialize();

        if (book != 'alice') {
          final response = await http.get(Uri.parse('$origin/$book.epub'));
          expect(response.statusCode, 200);
          app.bytes['epub'] = response.bodyBytes;
          final title = book == 'pride' ? 'Pride and Prejudice' : 'SQL Performance Explained';
          final storedBook = (await app.database.getById('epub'))!;
          await app.store.updateBookAndWait(storedBook.copyWith(title: title));
        }

        final opening = Completer<void>();
        await tester.pumpWidget(app.build(mediaGate: opening.future));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open epub'));

        for (var frame = 0; frame < 100 && find.byType(CircularProgressIndicator).evaluate().isEmpty; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byTooltip('Back'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }

        await binding.takeScreenshot('reader-$book-opening-native');
        opening.complete();
        await waitForReader(tester);
        expect(find.text('0%'), findsOneWidget);
        await binding.takeScreenshot('reader-$book-cover-native');
        final content = find.byKey(const ValueKey('reader-content'));
        final bounds = tester.getRect(content);
        final started = Stopwatch()..start();
        await tester.tap(find.byTooltip('Next'));

        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('Preparing pages…'), findsNothing);
          expect(find.byType(PageView), findsOneWidget);
        }

        await tester.pumpAndSettle();
        timings['${book}_turn_and_observation_ms'] = started.elapsedMilliseconds;
        expect(find.text('50%'), findsNothing);
        expect(find.text('7%'), findsNothing);
        await tester.tap(find.byTooltip('Previous'));
        await tester.pumpAndSettle();
        expect(find.text('0%'), findsOneWidget);
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Reading settings'));
        await tester.pumpAndSettle();
        expect(find.text('Preparing pages…'), findsNothing);
        expect(tester.getRect(content), bounds);
        expect(find.byType(AppBottomSheet), findsOneWidget);
        await binding.takeScreenshot('reader-$book-settings-sheet-native');
        await tester.fling(find.byType(BottomSheetHeader), const Offset(0, 650), 1500);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Table of contents'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsOneWidget);
        expect(tester.getRect(content), bounds);
        await binding.takeScreenshot('reader-$book-contents-sheet-native');
        await tester.drag(
          find.descendant(of: find.byType(AppBottomSheet), matching: find.byType(ListView)),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(AppBottomSheet), matching: find.byType(ListTile)).first);
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsNothing);
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        await tester.tapAt(bounds.center);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tester.getRect(content), bounds);
        expect(find.byTooltip('Show controls'), findsNothing);
        expect(find.byTooltip('Reading settings'), findsNothing);
        await binding.takeScreenshot('reader-$book-hidden-native');
        await tester.tapAt(bounds.center);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Reading settings'), findsOneWidget);
        final location = tester.widget<Text>(find.textContaining(RegExp(r'Chapter \d+ of'))).data;
        await binding.takeScreenshot('reader-$book-native');
        await tester.tap(find.byTooltip('Back').first);
        await tester.pumpAndSettle();
        Object? position;
        for (var attempt = 0; attempt < 50 && position == null; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          position = (await app.database.getById('epub'))?.customMetadata?['reader_locator'];
        }
        expect(position, isNotNull, reason: 'The client must persist its locator before reopening');
        await tester.tap(find.text('Open epub'));
        await waitForReader(tester);
        expect(app.store.getBook('epub')!.customMetadata?['reader_locator'], position);
        expect(find.text(location!), findsOneWidget);

        if (book == 'alice') {
          await tester.tap(find.byTooltip('Back').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open pdf'));
          await waitForReader(tester, pdf: true);
          await tester.tap(find.byTooltip('Reading settings'));
          await tester.pumpAndSettle();
          expect(find.byType(AppBottomSheet), findsOneWidget);
          await binding.takeScreenshot('reader-pdf-settings-sheet-native');
          await tester.fling(find.byType(BottomSheetHeader), const Offset(0, 650), 1500);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('reader-pdf-native');
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      }

      binding.reportData = {...?binding.reportData, 'reader_timings': timings};
    },
    skip: !runReaderValidation,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> waitForReader(WidgetTester tester, {bool pdf = false}) async {
  for (var frame = 0; frame < 150; frame++) {
    await tester.pump(const Duration(milliseconds: 100));

    if (find.byType(PapyrusReader).evaluate().isNotEmpty &&
        find.byTooltip('Next').evaluate().isNotEmpty &&
        (pdf || find.byType(PageView).evaluate().isNotEmpty)) {
      await tester.pumpAndSettle();
      return;
    }
  }

  fail('The reader did not become ready');
}
