import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/book_annotations.dart';
import 'package:papyrus/widgets/book/book_bookmarks.dart';
import 'package:papyrus/widgets/book/book_notes.dart';
import 'package:papyrus/widgets/book_details/empty_annotations_state.dart';
import 'package:papyrus/widgets/book_details/empty_bookmarks_state.dart';
import 'package:papyrus/widgets/book_details/empty_notes_state.dart';
import 'package:papyrus/widgets/dashboard/continue_reading_card.dart';
import 'package:papyrus/widgets/dashboard/reading_goal_card.dart';
import 'package:papyrus/widgets/dashboard/recently_added_section.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/statistics/reading_charts.dart';

void main() {
  for (final isPhysical in [false, true]) {
    for (final width in [400.0, 1200.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${isPhysical ? 'physical' : 'digital'} book tabs align their empty messages at the top at $width, scale $scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            addTearDown(tester.view.reset);
            var calls = 0;
            final tabs = [
              (BookNotes(notes: const [], onAddNote: () => calls++), Icons.note_outlined, 'Add note'),
              (
                BookBookmarks(
                  bookmarks: const [],
                  bookTitle: 'Book',
                  isPhysical: isPhysical,
                  onAddBookmark: () => calls++,
                ),
                Icons.bookmark_outline,
                'Add bookmark',
              ),
              (
                BookAnnotations(annotations: const [], isPhysical: isPhysical, onAddAnnotation: () => calls++),
                Icons.highlight_outlined,
                'Add annotation',
              ),
            ];
            for (final (tab, icon, action) in tabs) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.dark,
                  home: MediaQuery(
                    data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
                    child: Scaffold(body: SizedBox(height: 800, child: tab)),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(tester.getTopLeft(find.byIcon(icon)).dy, Spacing.xl);
              if (isPhysical || action == 'Add note') {
                expect(find.text(action).hitTestable(), findsOneWidget);
                await tester.tap(find.text(action));
              } else {
                expect(find.text(action), findsNothing);
              }
            }
            expect(calls, isPhysical ? 3 : 1);
          },
        );
      }
    }
  }

  const states = <String, Widget>{
    'No annotations yet': EmptyAnnotationsState(isPhysical: true),
    'No bookmarks yet': EmptyBookmarksState(isPhysical: true),
    'No notes yet': EmptyNotesState(),
    'No book in progress': ContinueReadingCard(),
    'No reading goals set': ReadingGoalCard(goals: []),
    'No books added recently': RecentlyAddedSection(books: []),
    'No reading data for this period': ReadingTimeBarChart(activities: []),
    'No books read data available': BooksPerMonthChart(monthlyStats: []),
  };

  for (final entry in states.entries) {
    for (final theme in [AppTheme.dark, AppTheme.eink]) {
      testWidgets('${entry.key} fits a narrow panel at large text in ${theme.brightness}', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: SizedBox(width: 280, height: 200, child: entry.value)),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(EmptyState), findsOneWidget);
        final title = tester.widget<Text>(find.text(entry.key));
        expect(title.style?.color, theme.colorScheme.onSurfaceVariant);
        expect(title.textAlign, TextAlign.center);
        // The original card message/action can still be reached when it is tall.
        for (final scroll in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
        }
        await tester.pump();
        final action = find.byType(EmptyStateAction);
        if (action.evaluate().isNotEmpty) {
          expect(find.descendant(of: action, matching: find.byType(FilledButton)).hitTestable(), findsOneWidget);
        }
      });
    }
  }

  testWidgets('empty dashboard cards support the intrinsic height used by the desktop row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ContinueReadingCard(isDesktop: true)),
                  Expanded(child: ReadingGoalCard(goals: [], isDesktop: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Browse library').hitTestable(), findsOneWidget);
    expect(find.text('Set a goal').hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byType(ContinueReadingCard)).height,
      tester.getSize(find.byType(ReadingGoalCard)).height,
    );
  });
}
