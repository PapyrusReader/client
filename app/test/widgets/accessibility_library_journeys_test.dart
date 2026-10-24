import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/pages/book_edit_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/add_book/book_import_sheet_sections.dart';
import 'package:papyrus/widgets/add_book/book_import_batch_item.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [2.0, 4.0]) {
      for (final editing in [false, true]) {
        testWidgets('${editing ? 'editing' : 'details'} actions remain reachable at $width and ${scale}x', (
          tester,
        ) async {
          final size = Size(width, 900);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final book = buildTestBook(id: 'book', title: 'A book with a longer title', author: 'An Author');
          await tester.pumpWidget(
            createTestPage(
              dataStore: createTestDataStore(books: [book]),
              screenSize: size,
              page: Theme(
                data: AppTheme.light,
                child: MediaQuery(
                  data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: editing ? const BookEditPage(id: 'book') : const BookDetailsPage(id: 'book'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          if (editing) {
            final title = find.byWidgetPredicate(
              (widget) => widget is TextFormField && widget.controller?.text == book.title,
            );
            await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);
            await tester.pumpAndSettle();
            await tester.enterText(title, 'Changed title');
            await tester.pumpAndSettle();
            final save = find.widgetWithText(FilledButton, 'Save');
            expect(save.hitTestable(), findsOneWidget);
          } else {
            final edit = find.byTooltip('Edit book');
            await tester.ensureVisible(edit);
            await tester.pumpAndSettle();
            expect(edit.hitTestable(), findsOneWidget);
          }
        });
      }
      testWidgets('file import can browse and remove at $width and ${scale}x', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var browsed = false;
        var removed = false;
        final file = SelectedBookFile(name: 'An accessible book.epub', bytes: Uint8List.fromList([1]));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: BookImportSelectingSection(
                files: [file],
                readableFiles: [file],
                isPicking: false,
                onBrowse: () => browsed = true,
                onDroppedFiles: (_, {feedback}) {},
                onRemoveFile: (_) => removed = true,
                onClearSelection: () {},
                onStartImport: () {},
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Add files'),
          200,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add files'));
        expect(browsed, isTrue);
        await tester.scrollUntilVisible(
          find.byTooltip('Remove ${file.name}'),
          200,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove ${file.name}'));
        expect(removed, isTrue);
      });
    }
  }
}
