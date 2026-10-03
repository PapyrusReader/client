import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/add_book/add_physical_book_sheet.dart';
import 'package:papyrus/widgets/library/library_advanced_filter_sheet.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';
import 'package:papyrus/widgets/shelves/add_shelf_sheet.dart';
import 'package:papyrus/widgets/shelves/move_to_shelf_sheet.dart';
import 'package:papyrus/widgets/topics/manage_topics_sheet.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext) show, {
    DataStore? store,
    Size size = const Size(375, 812),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final dataStore = store ?? (DataStore()..loadData(shelves: const [], tags: const []));
    addTearDown(dataStore.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: dataStore,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => show(context), child: const Text('Open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final size in [const Size(375, 812), const Size(1280, 800)]) {
    testWidgets('advanced filters footer resets the draft without closing at $size', (tester) async {
      final library = LibraryProvider()..applyFilters(LibraryFilters(favoriteFilter: FavoriteFilter.favorites));
      addTearDown(library.dispose);
      final store = DataStore()..loadData(books: createTestBooks());
      LibraryFilters? result;
      await openSheet(
        tester,
        (context) async {
          result = await LibraryAdvancedFilterSheet.show(context, libraryProvider: library, dataStore: store);
        },
        store: store,
        size: size,
      );
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Show 2 books'), findsOneWidget);
      final reset = find.descendant(
        of: find.byType(BottomSheetFooter),
        matching: find.widgetWithText(OutlinedButton, 'Reset'),
      );
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryAdvancedFilterSheet), findsOneWidget);
      expect(find.text('Show 5 books'), findsOneWidget);
      expect(library.filters.favoriteFilter, FavoriteFilter.favorites);
      expect(result, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Show 5 books'));
      await tester.pumpAndSettle();
      expect(result, LibraryFilters());
      expect(find.byType(LibraryAdvancedFilterSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  final longSheets = <String, void Function(BuildContext)>{
    'goal': (context) => AddGoalSheet.show(context),
    'physical book': (context) => AddPhysicalBookSheet.show(context),
    'shelf editor': (context) => AddShelfSheet.show(context),
    'shelf selection': (context) => MoveToShelfSheet.show(context, book: buildTestBook()),
    'topic selection': (context) => ManageTopicsSheet.show(context, book: buildTestBook()),
    'advanced filters': (context) {
      final library = LibraryProvider();
      LibraryAdvancedFilterSheet.show(context, libraryProvider: library, dataStore: context.read<DataStore>());
    },
  };
  for (final entry in longSheets.entries) {
    testWidgets('${entry.key} expands before scrolling on mobile', (tester) async {
      final store = DataStore()
        ..loadData(
          books: createTestBooks(),
          shelves: List.generate(20, (i) => buildTestShelf(id: 'shelf-$i', name: 'Shelf $i')),
          tags: List.generate(20, (i) => buildTestTag(id: 'topic-$i', name: 'Topic $i')),
        );
      await openSheet(tester, entry.value, store: store);
      expect(find.byType(ExpandableBottomSheet), findsOneWidget);
      final header = find.byKey(Key(entry.key == 'physical book' ? 'add-book-sheet-header' : 'bottom-sheet-header'));
      final initialTop = tester.getTopLeft(header).dy;
      expect(initialTop, greaterThan(24));
      final scrollable = find
          .descendant(of: find.byType(ExpandableBottomSheet), matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final footer = entry.key == 'physical book'
          ? find.byKey(const Key('add-book-sheet-footer'))
          : find.byType(BottomSheetFooter);
      final footerBottom = tester.getBottomRight(footer).dy;
      await tester.drag(scrollable, const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, lessThan(initialTop));
      expect(position.pixels, 0);
      await tester.drag(scrollable, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, closeTo(24, 1));
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0));
      expect(tester.getBottomRight(footer).dy, footerBottom);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short sheets stay fitted to content when scrolled', (tester) async {
    await openSheet(
      tester,
      (context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => AppBottomSheet(
          title: 'A short sheet',
          footer: BottomSheetFormActions(onCancel: () {}, onSave: () {}),
          body: const Text('Everything is visible.'),
        ),
      ),
    );
    final draggable = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
    expect(draggable.initialChildSize, lessThan(.8));
    expect(draggable.maxChildSize, draggable.initialChildSize);
    final header = find.byKey(const Key('bottom-sheet-header'));
    final initialTop = tester.getTopLeft(header).dy;
    final scrollable = find.byType(Scrollable);
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, initialTop);
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium content stops expanding once everything fits', (tester) async {
    await openSheet(
      tester,
      (context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => AppBottomSheet(
          title: 'Medium sheet',
          footer: BottomSheetFormActions(onCancel: () {}, onSave: () {}),
          body: const SizedBox(height: 500, child: Text('Content')),
        ),
      ),
    );
    final draggable = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
    expect(draggable.maxChildSize, greaterThan(.8));
    expect(draggable.maxChildSize, lessThan(1));
    final scrollable = find.byType(Scrollable);
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('bottom-sheet-header'))).dy, greaterThan(24));
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sheets keep content sizing and ordinary scrolling', (tester) async {
    await openSheet(tester, (context) => AddGoalSheet.show(context), size: const Size(1280, 800));
    expect(find.byType(ExpandableBottomSheet), findsNothing);
    final header = find.byKey(const Key('bottom-sheet-header'));
    final top = tester.getTopLeft(header).dy;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, top);
    expect(tester.takeException(), isNull);
  });
}
