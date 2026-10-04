import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';

void main() {
  group('EmptyState', () {
    Widget buildEmptyState({
      IconData icon = Icons.library_books_outlined,
      String title = 'No books found',
      String? subtitle,
      Widget? action,
      double iconSize = 64,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: icon, title: title, subtitle: subtitle, action: action, iconSize: iconSize),
        ),
      );
    }

    testWidgets('displays icon', (tester) async {
      await tester.pumpWidget(buildEmptyState(icon: Icons.library_books_outlined));
      expect(find.byIcon(Icons.library_books_outlined), findsOneWidget);
    });

    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(buildEmptyState(title: 'No books found'));
      expect(find.text('No books found'), findsOneWidget);
    });

    testWidgets('displays subtitle when provided', (tester) async {
      await tester.pumpWidget(buildEmptyState(subtitle: 'Try adjusting your filters'));
      expect(find.text('Try adjusting your filters'), findsOneWidget);
    });

    testWidgets('does not display subtitle when null', (tester) async {
      await tester.pumpWidget(buildEmptyState(subtitle: null));
      // Only title should be present, no subtitle text
      expect(find.text('No books found'), findsOneWidget);
    });

    testWidgets('displays action widget when provided', (tester) async {
      await tester.pumpWidget(
        buildEmptyState(
          action: ElevatedButton(onPressed: () {}, child: const Text('Add books')),
        ),
      );
      expect(find.text('Add books'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('does not display action when null', (tester) async {
      await tester.pumpWidget(buildEmptyState(action: null));
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('is centered', (tester) async {
      await tester.pumpWidget(buildEmptyState());
      // EmptyState contains a Center widget
      expect(find.byType(Center), findsAtLeastNWidgets(1));
    });

    testWidgets('uses custom icon size', (tester) async {
      await tester.pumpWidget(buildEmptyState(iconSize: 100));
      final icon = tester.widget<Icon>(find.byIcon(Icons.library_books_outlined));
      expect(icon.size, 100);
    });

    testWidgets('uses different icons', (tester) async {
      await tester.pumpWidget(buildEmptyState(icon: Icons.search_off));
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });
  });

  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    testWidgets('full and compact states share their palette in ${theme.brightness}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: EmptyState(icon: Icons.shelves, title: 'Full title', subtitle: 'Full description'),
                ),
                Expanded(
                  child: EmptyState.compact(
                    icon: Icons.library_books_outlined,
                    title: 'Compact title',
                    subtitle: 'Compact description',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final fullIcon = tester.widget<Icon>(find.byIcon(Icons.shelves));
      final compactIcon = tester.widget<Icon>(find.byIcon(Icons.library_books_outlined));
      expect(fullIcon.color, compactIcon.color);
      expect(fullIcon.color, theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5));
      final title = tester.widget<Text>(find.text('Full title'));
      final compactTitle = tester.widget<Text>(find.text('Compact title'));
      expect(title.style?.color, compactTitle.style?.color);
      expect(title.style?.color, theme.colorScheme.onSurfaceVariant);
      expect(
        tester.widget<Text>(find.text('Full description')).style,
        tester.widget<Text>(find.text('Compact description')).style,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('message and action remain reachable in a short viewport with large text', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 280,
              height: 200,
              child: EmptyState(
                icon: Icons.shelves,
                title: 'No shelves yet',
                subtitle: 'Create shelves to organize your books into collections',
                action: EmptyStateAction(label: 'Create shelf', icon: Icons.add, onPressed: () => called = true),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('Create shelf').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Create shelf'));
    expect(called, isTrue);
    expect(tester.takeException(), isNull);
  });
}
