import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/book_edit_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('BookEditPage layout', () {
    Future<void> pumpPage(WidgetTester tester, {required Size size}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final book = buildTestBook(
        id: 'book-1',
        title: 'Frankenstein; or, The Modern Prometheus',
        author: 'Mary Shelley',
      );

      await tester.pumpWidget(
        createTestPage(
          page: Theme(
            data: AppTheme.dark,
            child: const BookEditPage(id: 'book-1'),
          ),
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

    testWidgets('desktop keeps the cover and form fields side by side', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));

      final coverHeading = tester.getTopLeft(find.text('Cover'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));

      expect(formHeading.dx, greaterThan(coverHeading.dx));
      expect((formHeading.dy - coverHeading.dy).abs(), lessThan(4));
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
