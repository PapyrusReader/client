import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/book_edit_page.dart';
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

      final coverHeading = tester.getTopLeft(find.text('Cover'));
      expect(coverHeading.dx, lessThan(80));

      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(find.ancestor(of: saveButton, matching: find.byType(SingleChildScrollView)), findsNothing);
    });

    testWidgets('desktop keeps the cover beside metadata and form sections', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));

      final coverHeading = tester.getTopLeft(find.text('Cover'));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));

      expect(metadataHeading.dx, greaterThan(coverHeading.dx));
      expect((metadataHeading.dy - coverHeading.dy).abs(), lessThan(4));
      expect(formHeading.dx, closeTo(metadataHeading.dx, 1));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
    });

    testWidgets('intermediate desktop keeps panes side by side while paired fields stack', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 800);

      final coverHeading = tester.getTopLeft(find.text('Cover'));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final publisher = tester.getTopLeft(find.text('Publisher'));
      final language = tester.getTopLeft(find.text('Language'));

      expect(metadataHeading.dx, greaterThan(coverHeading.dx));
      expect((metadataHeading.dy - coverHeading.dy).abs(), lessThan(4));
      expect(language.dy, greaterThan(publisher.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium desktop centers the cover above full-width metadata and form sections', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);

      final coverHeading = tester.getTopLeft(find.text('Cover'));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));
      final coverCard = find.ancestor(of: find.text('Cover'), matching: find.byType(Card)).first;
      final metadataCard = find.ancestor(of: find.text('Fetch metadata'), matching: find.byType(Card)).first;
      final formCard = find.ancestor(of: find.text('Basic information'), matching: find.byType(Card)).first;

      expect(metadataHeading.dy, greaterThan(coverHeading.dy));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
      expect(tester.getCenter(coverCard).dx, closeTo(320, 1));
      expect(tester.getCenter(metadataCard).dx, closeTo(320, 1));
      expect(tester.getSize(metadataCard).width, closeTo(tester.getSize(formCard).width, 1));
      expect(tester.getSize(find.byType(AspectRatio).first).width, 240);
      expect(tester.takeException(), isNull);
    });

    testWidgets('metadata search precedes a compact visible source selector', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);

      final metadataCard = find.ancestor(of: find.text('Fetch metadata'), matching: find.byType(Card)).first;
      final searchField = find.ancestor(of: find.text('Search'), matching: find.byType(TextFormField)).first;
      final selector = find.byWidgetPredicate((widget) => widget is SegmentedButton);
      final sourceLabel = find.text('Source');

      expect(sourceLabel, findsOneWidget);
      expect(tester.getSize(searchField).width, closeTo(tester.getSize(metadataCard).width - (Spacing.md * 2), 1));
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
