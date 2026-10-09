import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/input/search_field.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/shelves/move_to_shelf_sheet.dart';
import 'package:papyrus/widgets/topics/manage_topics_sheet.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

void main() {
  final dataStore = DataStore()..loadData(shelves: const [], tags: const []);

  Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      createTestPage(
        page: Scaffold(body: sheet),
        dataStore: dataStore,
        screenSize: const Size(800, 1200),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('topics empty state is centered across the sheet', (tester) async {
    await pumpSheet(tester, const ManageTopicsSheet(bulkBookIds: ['book-1']));
    final title = find.text('No topics yet');
    expect(title, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(400, 20));
  });

  testWidgets('shelves empty state is present and centered across the sheet', (tester) async {
    await pumpSheet(tester, const MoveToShelfSheet(bulkBookIds: ['book-1']));
    final title = find.text('No shelves yet');
    expect(title, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(400, 20));
  });

  for (final topics in [false, true]) {
    for (final size in [const Size(375, 667), const Size(320, 568), const Size(1280, 800), const Size(1024, 400)]) {
      testWidgets(
        '${topics ? 'topics' : 'shelves'} empty message fits completely at $size without search or scrolling',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);

          if (size.width == 320) {
            tester.platformDispatcher.textScaleFactorTestValue = 1.5;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          }

          final store = DataStore()..loadData(shelves: const [], tags: const []);
          addTearDown(store.dispose);
          final book = buildTestBook(title: 'A long book title that must remain in the header');

          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: store,
              child: MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => topics
                          ? ManageTopicsSheet.show(context, book: book)
                          : MoveToShelfSheet.show(context, book: book),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(SearchField), findsNothing);
          final empty = tester.getRect(find.byType(EmptyState));
          final header = tester.getRect(find.byKey(const Key('bottom-sheet-header')));
          final footer = tester.getRect(find.byType(BottomSheetFooter));
          expect(empty.top, greaterThanOrEqualTo(header.bottom));
          expect(empty.bottom, lessThanOrEqualTo(footer.top), reason: 'empty=$empty header=$header footer=$footer');

          expect(
            find.text(topics ? 'Tap + to create a topic' : 'Tap + to create a shelf').hitTestable(),
            findsOneWidget,
          );

          for (final scroll in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
            expect(scroll.position.maxScrollExtent, 0);
          }
        },
      );
    }

    testWidgets(
      '${topics ? 'topics' : 'shelves'} search stays available for no matches and disappears for an empty collection',
      (tester) async {
        final store = DataStore()
          ..loadData(shelves: topics ? const [] : [buildTestShelf()], tags: topics ? [buildTestTag()] : const []);

        addTearDown(store.dispose);

        await tester.pumpWidget(
          createTestPage(
            page: Scaffold(
              body: topics
                  ? const ManageTopicsSheet(bulkBookIds: ['book'])
                  : const MoveToShelfSheet(bulkBookIds: ['book']),
            ),
            dataStore: store,
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(SearchField), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'no matches');
        await tester.pumpAndSettle();
        expect(find.text(topics ? 'No topics found' : 'No shelves found'), findsOneWidget);
        expect(find.byType(SearchField), findsOneWidget);
        store.loadData(shelves: const [], tags: const []);
        await tester.pumpAndSettle();
        expect(find.byType(SearchField), findsNothing);
        expect(find.byType(EmptyState), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
