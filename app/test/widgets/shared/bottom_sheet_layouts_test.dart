import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book_details/bookmark_dialog.dart';
import 'package:papyrus/widgets/book_details/annotation_dialog.dart';
import 'package:papyrus/widgets/book_details/note_dialog.dart';
import 'package:papyrus/widgets/book_details/update_progress_sheet.dart';
import 'package:papyrus/widgets/goals/add_goal_sheet.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shelves/add_shelf_sheet.dart';
import 'package:papyrus/widgets/shelves/move_to_shelf_sheet.dart';
import 'package:papyrus/widgets/topics/add_topic_sheet.dart';
import 'package:papyrus/widgets/topics/manage_topics_sheet.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_helpers.dart';

GoalsProvider goalProvider(BuildContext context) {
  final provider = GoalsProvider(watchClock: false)..attach(context.read<DataStore>());
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  final book = buildTestBook(title: 'A long book title for checking compact sheet headers');
  final launchers = <String, void Function(BuildContext)>{
    'shelf assignment': (context) => MoveToShelfSheet.show(context, book: book),
    'topic assignment': (context) => ManageTopicsSheet.show(context, book: book),
    'shelf form': (context) => AddShelfSheet.show(context),
    'topic form': (context) => AddTopicSheet.show(context),
    'goal form': (context) =>
        AddGoalSheet.show(context, provider: goalProvider(context), preset: 0, initialTimezone: 'UTC'),
    'bookmark form': (context) => BookmarkDialog.show(context, bookId: book.id),
    'annotation form': (context) => AnnotationDialog.show(context, bookId: book.id),
    'note form': (context) => NoteDialog.show(context, bookId: book.id),
    'progress form': (context) => UpdateProgressSheet.show(context, book: book, onSave: (_, _) {}),
  };

  for (final keyboard in [false, true]) {
    for (final entry in launchers.entries) {
      testWidgets('${entry.key} fits a narrow screen${keyboard ? ' with keyboard and larger text' : ''}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 240 : 0);
        tester.platformDispatcher.textScaleFactorTestValue = keyboard ? 1.5 : 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = DataStore()..loadData(shelves: const [], tags: const []);
        addTearDown(store.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: store,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(onPressed: () => entry.value(context), child: const Text('Open')),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final footer = find.byType(BottomSheetFooter);
        expect(footer, findsOneWidget);
        expect(tester.getRect(footer).bottom, lessThanOrEqualTo(keyboard ? 328 : 568));
        final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
        final primary = find.descendant(of: footer, matching: find.byType(FilledButton));
        expect(cancel.hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(cancel).dy, tester.getTopLeft(primary).dy);
        expect(tester.getSize(primary).height, greaterThanOrEqualTo(50));
        // The body can scroll independently while the buttons remain reachable.
        final footerTop = tester.getTopLeft(footer).dy;
        final bodyScroll = find.descendant(of: find.byType(AppBottomSheet), matching: find.byType(Scrollable)).first;
        await tester.drag(bodyScroll, const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(footer).dy, footerTop);
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsNothing);
      });
    }
  }
}
