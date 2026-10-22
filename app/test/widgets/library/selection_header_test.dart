import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/bulk_action_bar.dart';
import 'package:papyrus/widgets/library/selection_header.dart';

void main() {
  for (final width in [800.0, 1600.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final shelf in [false, true]) {
        testWidgets('bulk actions align to trailing margin at $width/$scale, shelf $shelf', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 850);
          addTearDown(tester.view.reset);
          var selectedAll = false;
          var actionPressed = false;

          await tester.pumpWidget(
            MaterialApp(
              theme: (scale == 1 ? AppTheme.dark : AppTheme.eink).copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(size: Size(width, 850), textScaler: TextScaler.linear(scale)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SelectionHeader(
                        selectedCount: 2,
                        totalCount: 6,
                        onClose: () {},
                        onSelectAll: () => selectedAll = true,
                        onDeselectAll: () {},
                        actions: BulkActionBar(
                          onDelete: shelf ? null : () => actionPressed = true,
                          onRemoveFromShelf: shelf ? () => actionPressed = true : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          final actions = tester.getRect(find.byType(BulkActionBar));
          final close = tester.getRect(find.byTooltip('Exit selection'));
          expect(actions.right, width - 24);
          expect(actions.center.dy, close.center.dy);
          expect(tester.getRect(find.text('Select all')).right, lessThan(actions.left));
          await tester.tap(find.text('Select all'));
          await tester.tap(find.byTooltip(shelf ? 'Remove from shelf' : 'Delete'));
          expect(selectedAll, isTrue);
          expect(actionPressed, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
