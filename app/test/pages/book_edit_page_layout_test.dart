import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/book_edit_page.dart';
import 'package:papyrus/providers/book_edit_provider.dart';
import 'package:papyrus/widgets/book_details/book_info_grid.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('BookEditPage layout', () {
    Future<void> pumpPage(WidgetTester tester, {required Size size, double? contentWidth}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final book = buildTestBook(
        id: 'book-1',
        title: 'Frankenstein; or, The Modern Prometheus',
        author: 'Mary Shelley',
      );

      Widget page = Theme(
        data: AppTheme.dark,
        child: const BookEditPage(id: 'book-1'),
      );

      if (contentWidth != null) {
        page = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: contentWidth, height: size.height, child: page),
        );
      }

      await tester.pumpWidget(
        createTestPage(
          page: page,
          dataStore: createTestDataStore(books: [book]),
          screenSize: size,
        ),
      );

      await tester.pumpAndSettle();
    }

    for (final width in [390.0, 1400.0]) {
      testWidgets('genre can be edited and cleared at $width', (tester) async {
        await pumpPage(tester, size: Size(width, 1000));
        final field = find.ancestor(of: find.text('Genre'), matching: find.byType(TextFormField));
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Science fiction');
        final editor = tester.element(field).read<BookEditProvider>();
        expect(editor.editedBook?.genre, 'Science fiction');
        expect(await editor.save(), isTrue);
        final saved = editor.editedBook!;
        await tester.enterText(field, '');
        expect(editor.editedBook?.genre, isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: BookInfoGrid(book: saved)),
          ),
        );
        expect(find.text('Genre'), findsOneWidget);
        expect(find.text('Science fiction'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop uses a left-aligned page header with a persistent Save action', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));
      expect(find.text('Edit book'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsNothing);
      expect(find.byTooltip('Back to book details'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsNothing);
      final header = find.byKey(const Key('book-edit-desktop-header'));
      expect(tester.getSize(header).height, ComponentSizes.appBarHeight);
      expect(find.descendant(of: header, matching: find.text('Frankenstein; or, The Modern Prometheus')), findsNothing);
      expect(find.text('Cover'), findsNothing);
      expect(tester.getTopLeft(find.byType(CoverImagePicker)).dx, Spacing.lg);
      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(find.ancestor(of: saveButton, matching: find.byType(SingleChildScrollView)), findsNothing);
    });

    testWidgets('desktop keeps the cover beside metadata and form sections', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));
      expect(metadataHeading.dx, greaterThan(cover.dx));

      expect(metadataHeading.dy, cover.dy);

      expect(formHeading.dx, closeTo(metadataHeading.dx, 1));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
    });

    testWidgets('intermediate desktop keeps panes side by side while paired fields stack', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 800);
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final publisher = tester.getTopLeft(find.text('Publisher'));
      final language = tester.getTopLeft(find.text('Language'));
      expect(metadataHeading.dx, greaterThan(cover.dx));

      expect(metadataHeading.dy, cover.dy);

      expect(language.dy, greaterThan(publisher.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium desktop aligns the cover with the page gutter above full-width form sections', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));
      final coverPreview = find.descendant(of: find.byType(CoverImagePicker), matching: find.byType(AspectRatio));
      expect(metadataHeading.dy, greaterThan(cover.dy));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
      expect(tester.getTopLeft(coverPreview).dx, Spacing.lg);
      expect(metadataHeading.dx, formHeading.dx);
      expect(tester.getSize(find.byType(AspectRatio).first).width, 240);
      expect(tester.takeException(), isNull);
    });

    testWidgets('metadata search precedes a compact visible source selector', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);
      final searchField = find.ancestor(of: find.text('Search'), matching: find.byType(TextFormField)).first;
      final selector = find.byWidgetPredicate((widget) => widget is SegmentedButton);
      final sourceLabel = find.text('Source');
      expect(sourceLabel, findsOneWidget);
      expect(tester.getTopLeft(sourceLabel).dy, greaterThan(tester.getTopLeft(searchField).dy));
      expect((tester.getCenter(selector).dy - tester.getCenter(sourceLabel).dy).abs(), lessThan(1));
    });

    testWidgets('metadata source selector does not reserve width for a selected icon', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);
      final selector = find.byWidgetPredicate((widget) => widget is SegmentedButton);
      expect(find.descendant(of: selector, matching: find.byIcon(Icons.check)), findsNothing);
    });

    testWidgets('narrow layouts stack the cover above the form without overflow', (tester) async {
      await pumpPage(tester, size: const Size(600, 1600));
      expect(find.text('Edit book'), findsOneWidget);
      expect(find.byType(CoverImagePicker), findsOneWidget);

      expect(
        tester.getTopLeft(find.byType(CoverImagePicker)).dy,
        lessThan(tester.getTopLeft(find.text('Basic information')).dy),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
