import 'dart:typed_data';
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/add_book/book_import_batch_item.dart';
import 'package:papyrus/widgets/add_book/book_import_sheet.dart';
import 'package:papyrus/services/book_import_result.dart';
import 'package:papyrus/widgets/add_book/book_import_drop_zone.dart';
import 'package:papyrus/widgets/add_book/book_import_item_card.dart';

void main() {
  testWidgets('route back waits for late processing and temporary file cleanup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final processed = Completer<BookImportResult>();
    final deleted = Completer<void>();
    final deletions = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => BookImportSheet.show(
                context,
                pickFiles: () async => [
                  SelectedBookFile(name: 'book.epub', bytes: Uint8List.fromList([1])),
                ],
                processor: (_, _) => processed.future,
                deleteBookFile: (id) async {
                  deletions.add(id);
                  await deleted.future;
                },
                committer: (_, _) async => throw StateError('Closed imports must not commit'),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 1 book'));
    await tester.pump();
    await navigator.currentState!.maybePop();
    await tester.pump();
    expect(find.byType(BookImportSheet), findsOneWidget);
    processed.complete(
      const BookImportResult(
        bookId: 'temporary',
        title: 'Book',
        author: 'Author',
        fileSize: 1,
        fileHash: 'hash',
        fileExtension: 'epub',
      ),
    );
    await tester.pump();
    expect(deletions, ['temporary']);
    expect(find.byType(BookImportSheet), findsOneWidget);
    deleted.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BookImportSheet), findsNothing);
  });

  testWidgets('drop zone fills its body and shows desktop guidance', (tester) async {
    var browseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 360,
            child: BookImportDropZone(
              isPicking: false,
              onBrowse: () => browseCount++,
              onDroppedFiles: (_, {feedback}) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(BookImportDropZone)), const Size(600, 360));
    expect(find.text('Drag and drop book files here'), findsOneWidget);
    expect(find.text('EPUB, PDF, MOBI, AZW3, TXT, CBR, and CBZ'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Browse files')).width, lessThan(200));
    expect(tester.widget<Text>(find.text('Browse files')).maxLines, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Browse files'));
    expect(browseCount, 1);
  });

  testWidgets('drop zone keeps the resting surface color on pointer hover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: BookImportDropZone(isPicking: false, onBrowse: () {}, onDroppedFiles: (_, {feedback}) {}),
        ),
      ),
    );

    Color? surfaceColor() {
      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      return (container.decoration! as BoxDecoration).color;
    }

    final restingColor = surfaceColor();
    final focusable = tester.widget<FocusableActionDetector>(find.byType(FocusableActionDetector));
    focusable.onShowHoverHighlight?.call(true);
    await tester.pumpAndSettle();

    expect(surfaceColor(), restingColor);
  });

  testWidgets('drop zone uses picker guidance on mobile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: BookImportDropZone(isPicking: false, onBrowse: () {}, onDroppedFiles: (_, {feedback}) {}),
        ),
      ),
    );

    expect(find.text('Choose book files'), findsOneWidget);
    expect(find.text('Drag and drop book files here'), findsNothing);
  });

  testWidgets('drop zone reads supported files and reports skipped files', (tester) async {
    List<SelectedBookFile>? droppedFiles;
    String? dropFeedback;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Scaffold(
          body: BookImportDropZone(
            isPicking: false,
            onBrowse: () {},
            onDroppedFiles: (files, {feedback}) {
              droppedFiles = files;
              dropFeedback = feedback;
            },
          ),
        ),
      ),
    );

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(Uint8List.fromList([1, 2]), name: 'book.epub', path: 'book.epub'),
          DropItemFile.fromData(Uint8List.fromList([3]), name: 'notes.docx', path: 'notes.docx'),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(droppedFiles, hasLength(1));
    expect(droppedFiles!.single.name, 'book.epub');
    expect(droppedFiles!.single.bytes, [1, 2]);
    expect(dropFeedback, contains('skipped'));
  });

  testWidgets('failed import card prioritizes retry over remove', (tester) async {
    final item = BookImportBatchItem.queued(
      id: 'import-0',
      file: SelectedBookFile(name: 'failed.epub', bytes: Uint8List.fromList([1])),
    ).startProcessing().processingFailed('Could not parse file.');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookImportItemCard(
            item: item,
            presentation: BookImportItemCardPresentation.progress,
            onRetry: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Remove failed.epub'), findsNothing);
    expect(find.text('Could not parse file.'), findsOneWidget);
  });
}
