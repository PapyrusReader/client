import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/search/library_search_bar.dart';

void main() {
  for (final width in [320.0, 512.0, 599.0, 600.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('search and shelf action stay on one row at $width/$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        addTearDown(tester.view.reset);
        var pressed = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: scale == 1 ? AppTheme.dark : AppTheme.eink,
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(size: const Size(1200, 850), textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: LibraryToolbar(
                      search: const LibrarySearchBar(),
                      actions: [LibraryAddButton(label: 'Add to shelf', onPressed: () => pressed = true)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final search = tester.getRect(find.byType(LibrarySearchBar));
        final action = tester.getRect(find.byType(LibraryAddButton));
        expect(search.center.dy, action.center.dy);
        expect(search.right, lessThan(action.left));
        expect(search.width, greaterThan(160));
        expect(action.right, lessThanOrEqualTo(width));

        if (width < 600 || scale > 1.4) {
          expect(find.byTooltip('Add to shelf'), findsOneWidget);
        } else {
          expect(find.text('Add to shelf'), findsOneWidget);
        }

        await tester.tap(find.byType(LibraryAddButton));
        await tester.pumpAndSettle();
        expect(pressed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
