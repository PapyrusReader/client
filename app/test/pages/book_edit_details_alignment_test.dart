import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/pages/book_edit_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/book_details/book_header.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final layout in [
      (screen: const Size(3840, 2160), width: 3560.0, scale: 1.0),
      (screen: const Size(1800, 1200), width: 1520.0, scale: 1.0),
      (screen: const Size(1200, 1200), width: 920.0, scale: 1.0),
      (screen: const Size(1000, 1200), width: 800.0, scale: 1.0),
      (screen: const Size(1000, 1200), width: 640.0, scale: 1.0),
      (screen: const Size(840, 1200), width: 560.0, scale: 1.0),
      (screen: const Size(1200, 1200), width: 920.0, scale: 2.0),
      (screen: const Size(1000, 1200), width: 640.0, scale: 2.0),
    ]) {
      testWidgets('desktop details/edit covers match at ${layout.width}, scale ${layout.scale}, ${theme.brightness}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.screen;
        addTearDown(tester.view.reset);
        final store = createTestDataStore(
          books: [buildTestBook(id: 'book', title: 'A book', author: 'An author')],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
        });
        Future<void> pump(Widget page) async {
          await tester.pumpWidget(
            createTestPage(
              dataStore: store,
              screenSize: layout.screen,
              page: Theme(
                data: theme,
                child: MediaQuery(
                  data: MediaQueryData(size: layout.screen, textScaler: TextScaler.linear(layout.scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: SizedBox(width: layout.width, child: page),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await pump(const BookDetailsPage(id: 'book'));
        final reference = tester.getRect(
          find.descendant(of: find.byType(CoverImagePreview), matching: find.byType(CoverImage)),
        );
        expect(reference.size, const Size(240, 360));
        expect(reference.left, layout.screen.width - layout.width + Spacing.lg);

        final detailsTitle = tester.getRect(
          find.descendant(of: find.byType(BookHeader), matching: find.text('A book')).last,
        );
        final detailsGap = detailsTitle.left - reference.right;

        await pump(const BookEditPage(id: 'book'));
        final preview = find.descendant(of: find.byType(CoverImagePicker), matching: find.byType(AspectRatio));
        final image = find.descendant(of: find.byType(CoverImagePicker), matching: find.byType(CoverImage));
        expect(tester.getRect(preview), reference);
        expect(tester.getRect(image), reference, reason: 'Compare the image itself, including any decoration inset');
        expect(find.text('Cover'), findsNothing);
        final metadataHeading = tester.getRect(find.text('Fetch metadata'));
        if (layout.width >= ComponentSizes.bookCoverWidthDesktop + Spacing.md + 420 + Spacing.lg * 2) {
          expect(metadataHeading.left - reference.right, detailsGap);
          expect(metadataHeading.top, reference.top);
          expect(tester.getRect(find.text('Basic information')).left, detailsTitle.left);
          final search = find.ancestor(of: find.text('Search'), matching: find.byType(TextFormField)).first;
          expect(tester.getRect(search).left, detailsTitle.left);
        }
        final formCard = find.ancestor(of: find.text('Basic information'), matching: find.byType(Card)).first;
        expect(
          tester.getRect(formCard).right,
          layout.screen.width - layout.width + math.min(layout.width, 1120) - Spacing.lg,
        );
        expect(find.widgetWithText(OutlinedButton, 'Upload'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'URL'), findsOneWidget);
      });
    }
  }

  testWidgets('mobile edit retains its padded card and full-width bordered cover', (tester) async {
    const screen = Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);
    final store = createTestDataStore(books: [buildTestBook(id: 'book')]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
    await tester.pumpWidget(
      createTestPage(
        dataStore: store,
        screenSize: screen,
        page: Theme(
          data: AppTheme.dark,
          child: const BookEditPage(id: 'book'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = find.byType(CoverImagePicker);
    final preview = tester.getRect(find.descendant(of: picker, matching: find.byType(AspectRatio)));
    final image = tester.getRect(find.descendant(of: picker, matching: find.byType(CoverImage)));
    expect(tester.widget<CoverImagePicker>(picker).isDesktop, isFalse);
    expect(tester.widget<CoverImagePicker>(picker).coverWidth, isNull);
    expect(preview.left, Spacing.md * 2);
    expect(preview.top, tester.getRect(find.byType(AppBar)).bottom + Spacing.md * 2);
    expect(preview.width, screen.width - Spacing.md * 4);
    expect(preview.height, preview.width / CoverImagePicker.coverAspectRatio);
    expect(image, preview.deflate(1));
    expect(find.ancestor(of: picker, matching: find.byType(Card)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
