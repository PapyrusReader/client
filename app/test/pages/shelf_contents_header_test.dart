import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/shelf_contents_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/search/library_search_bar.dart';
import 'package:papyrus/widgets/shelves/shelf_info_sheet.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final theme in [AppTheme.dark, AppTheme.eink]) {
    for (final (width, scale) in [(320.0, 2.0), (400.0, 1.0), (1200.0, 1.0)]) {
      testWidgets('shelf header stays compact and description remains editable at $width/$scale/${theme.brightness}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        addTearDown(tester.view.reset);
        const description = 'Books for a long reading project, with a description that belongs in shelf details.';
        final shelf = buildTestShelf(name: 'A shelf with a long name for a reading project', description: description);
        final store = createTestDataStore(books: [], shelves: [shelf]);
        addTearDown(store.dispose);

        await tester.pumpWidget(
          createTestPage(
            dataStore: store,
            screenSize: Size(width, 850),
            page: Theme(
              data: theme,
              child: MediaQuery(
                data: MediaQueryData(size: Size(width, 850), textScaler: TextScaler.linear(scale)),
                child: ShelfContentsPage(shelfId: shelf.id),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final edit = width < 840 ? find.byTooltip('Edit') : find.widgetWithText(TextButton, 'Edit');
        final back = find.byTooltip('Back to shelves');
        final search = find.byType(LibrarySearchBar);
        expect(find.text(description), findsNothing);
        expect(find.text('Add a description'), findsNothing);
        expect(tester.getCenter(edit).dy, tester.getCenter(back).dy);
        expect(tester.getRect(edit).right, width - (width < 840 ? 16 : 24));
        expect(tester.getRect(search).top - tester.getRect(edit).bottom, scale == 2 ? 24 : 16);
        expect(tester.takeException(), isNull);
        final info = width < 840 ? find.byTooltip('Details') : find.widgetWithText(TextButton, 'Details');
        expect(tester.getCenter(info).dy, tester.getCenter(back).dy);
        await tester.tap(info);
        await tester.pumpAndSettle();
        expect(find.byType(ShelfInfoSheet), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(find.text('0 books'), findsNothing);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(ShelfInfoSheet))).pop();
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();

        expect(
          tester
              .widgetList<TextFormField>(find.byType(TextFormField))
              .any(
                (field) => field.controller?.text == description,
              ),
          isTrue,
        );

        expect(tester.takeException(), isNull);
      });
    }
  }
}
