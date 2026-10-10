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
import 'package:papyrus/widgets/add_book/book_import_sheet_sections.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';

void main() {
  testWidgets('mobile footer actions share a row and stay fixed while selecting more files', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    var picks = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => BookImportSheet.show(
                context,
                pickFiles: () async {
                  picks++;

                  return List.generate(
                    12,
                    (i) => SelectedBookFile(name: 'batch-$picks-$i.epub', bytes: Uint8List.fromList([1])),
                  );
                },
                processor: (_, _) async => throw StateError('Selection must not start import'),
                deleteBookFile: (_) async {},
                committer: (_, _) async => throw StateError('Selection must not commit'),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpandableBottomSheet), findsOneWidget);
    expect(tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet)).maxChildSize, lessThan(.8));
    final footer = find.byKey(const Key('add-book-sheet-footer'));
    final browse = find.widgetWithText(OutlinedButton, 'Browse files');
    final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
    final initialImport = find.widgetWithText(FilledButton, 'Import');
    expect(tester.getSize(initialImport).height, greaterThanOrEqualTo(50));
    expect(tester.getSize(cancel).height, tester.getSize(initialImport).height);
    expect(tester.getTopLeft(cancel).dy, tester.getTopLeft(initialImport).dy);
    expect(tester.getTopLeft(initialImport).dx - tester.getTopRight(cancel).dx, 8);

    final primaryShape = tester
        .widget<FilledButton>(initialImport)
        .defaultStyleOf(tester.element(initialImport))
        .shape!
        .resolve({});

    final secondaryShape = OutlinedButtonTheme.of(tester.element(cancel)).style!.shape!.resolve({});
    expect(primaryShape, secondaryShape);
    expect(primaryShape, isA<StadiumBorder>());
    expect(tester.widget<FilledButton>(initialImport).onPressed, isNull);
    expect(find.descendant(of: browse, matching: find.byType(Icon)), findsNothing);
    expect(find.text('Drag and drop book files here'), findsNothing);
    await tester.tap(browse);
    await tester.pumpAndSettle();
    final import = find.widgetWithText(FilledButton, 'Import');
    expect(find.text('12 files selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(import).onPressed, isNotNull);
    expect(tester.getTopLeft(import).dy, tester.getTopLeft(cancel).dy);
    expect(find.descendant(of: import, matching: find.byType(Icon)), findsNothing);
    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('24 files selected'), findsOneWidget);
    expect(tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet)).maxChildSize, 1);
    final footerTop = tester.getTopLeft(footer).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(footer).dy, footerTop);
    expect(tester.getTopLeft(find.byKey(const Key('add-book-sheet-header'))).dy, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('import selection fits a narrow screen with large text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);

    final files = [
      SelectedBookFile(name: 'a-long-book-filename.epub', bytes: Uint8List.fromList([1])),
    ];

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: BookImportSelectingSection(
            files: files,
            readableFiles: files,
            isPicking: false,
            onBrowse: () {},
            onDroppedFiles: (_, {feedback}) {},
            onRemoveFile: (_) {},
            onClearSelection: () {},
            onStartImport: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Import'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Remove a-long-book-filename.epub')).width, greaterThanOrEqualTo(48));
  });

  testWidgets('desktop selection retains browse in the body and matching footer actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: BookImportSelectingSection(
            files: const [],
            readableFiles: const [],
            isPicking: false,
            onBrowse: () {},
            onDroppedFiles: (_, {feedback}) {},
            onRemoveFile: (_) {},
            onClearSelection: () {},
            onStartImport: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    final browse = find.widgetWithText(OutlinedButton, 'Browse files');
    final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
    final import = find.widgetWithText(FilledButton, 'Import');
    expect(find.text('Browse files'), findsOneWidget);
    expect(tester.getTopLeft(cancel).dx, lessThan(tester.getTopLeft(import).dx));
    expect(tester.getTopLeft(import).dx - tester.getTopRight(cancel).dx, 16);
    final cancelPadding = OutlinedButtonTheme.of(tester.element(cancel)).style!.padding!.resolve({});
    final importPadding = FilledButtonTheme.of(tester.element(import)).style!.padding!.resolve({});
    expect(cancelPadding, const EdgeInsets.symmetric(horizontal: 24, vertical: 8));
    expect(importPadding, cancelPadding);
    expect(tester.getSize(cancel).height, tester.getSize(import).height);
    expect(tester.getSize(import).height, greaterThanOrEqualTo(50));
    expect(tester.getSize(cancel).width, lessThan(160));
    expect(tester.getSize(import).width, lessThan(280));
    final footer = find.byKey(const Key('add-book-sheet-footer'));
    expect(tester.getTopRight(import).dx, tester.getTopRight(footer).dx - 16);
    final secondaryShape = OutlinedButtonTheme.of(tester.element(cancel)).style!.shape!.resolve({});
    expect(secondaryShape, isA<StadiumBorder>());
    expect(find.descendant(of: browse, matching: find.byType(Icon)), findsNothing);
    expect(find.text('Drag and drop book files here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fromHandle in [false, true]) {
    testWidgets(
      '${fromHandle ? 'handle dismissal' : 'route back'} waits for late processing and temporary file cleanup',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = fromHandle ? const Size(390, 844) : const Size(800, 1200);
        addTearDown(tester.view.reset);
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
        await tester.tap(find.text('Import'));
        await tester.pump();

        if (fromHandle) {
          expect(find.byType(ExpandableBottomSheet), findsOneWidget);
          await tester.drag(find.byType(BottomSheetHandle), const Offset(0, 600));
        } else {
          await navigator.currentState!.maybePop();
        }

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
      },
    );
  }

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
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byType(DropTarget), findsNothing);
  });

  testWidgets('compact desktop browser uses the mobile file picker without clipping its button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var browseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              height: 180,
              child: BookImportDropZone(
                isPicking: false,
                onBrowse: () => browseCount++,
                onDroppedFiles: (_, {feedback}) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Choose book files'), findsOneWidget);
    expect(find.text('Drag and drop book files here'), findsNothing);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byType(DropTarget), findsNothing);
    final button = find.widgetWithText(OutlinedButton, 'Browse files');
    final pickerRect = tester.getRect(find.byType(BookImportDropZone));
    final buttonRect = tester.getRect(button);
    expect(buttonRect.top, greaterThanOrEqualTo(pickerRect.top));
    expect(buttonRect.bottom, lessThanOrEqualTo(pickerRect.bottom));
    expect(buttonRect.height, greaterThanOrEqualTo(50));
    await tester.tap(button);
    expect(browseCount, 1);
    expect(tester.takeException(), isNull);
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
