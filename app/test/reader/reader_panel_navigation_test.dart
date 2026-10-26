import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/reader/reader_panel_route.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

void main() {
  testWidgets('full-screen contents returns to the same reader and navigates to the selected chapter', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final facade = _PanelPdfFacade();
    var loads = 0;

    final controller = ReaderController(
      registry: ReaderEngineRegistry([
        ReaderEngineRegistration(
          formats: const {ReaderFormat.pdf},
          factory: () => PdfReaderEngine(facadeFactory: (_) async => facade),
        ),
      ]),
    );

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: PapyrusReader(
          document: ReaderDocument(
            id: 'contents',
            title: 'A book',
            format: ReaderFormat.pdf,
            loadBytes: () async {
              loads++;
              return Uint8List(0);
            },
          ),
          controller: controller,
          builders: ReaderUiBuilders(
            compactPanelRoute: (context, panel) => buildReaderPanelRoute(context, panel, bookTitle: 'A book'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final locator = controller.snapshot.locator;
    final viewport = find.byKey(const ValueKey('book-viewport'));
    final bounds = tester.getRect(viewport);
    expect(find.byTooltip('Table of contents'), findsNothing);
    await tester.tapAt(bounds.center);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Table of contents'));
    await tester.pumpAndSettle();
    expect(find.text('A book'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(controller.snapshot.locator, locator);
    expect(tester.getRect(viewport), bounds);
    await tester.tap(find.byTooltip('Table of contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second chapter'));
    await tester.pumpAndSettle();
    expect((controller.snapshot.locator as PdfReaderLocator).pageIndex, 12);
    expect(find.text('Contents'), findsNothing);
    expect(tester.getRect(viewport), bounds);
    expect(loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _PanelPdfFacade implements PdfFacade {
  @override
  int get pageCount => 80;

  @override
  List<PdfFacadeOutlineEntry> get outline => const [
    PdfFacadeOutlineEntry(title: 'First chapter', pageIndex: 0),
    PdfFacadeOutlineEntry(title: 'Second chapter', pageIndex: 12),
  ];

  @override
  Future<void> showPage(int pageIndex, double pageOffset) async {}

  @override
  Widget buildViewport(PdfViewportConfiguration configuration) => const SizedBox.expand(key: ValueKey('book-viewport'));
}
