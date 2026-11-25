import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/widgets/statistics/statistics_activity_tab.dart';
import 'package:papyrus/pages/statistics_page.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/statistics/reading_charts.dart';
import 'package:papyrus/widgets/statistics/stat_card.dart';
import 'package:provider/provider.dart';

Future<void> pumpStatistics(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  ThemeData? theme,
  bool empty = false,
  PreferencesProvider? preferences,
  DateTime? at,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final now = at ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final store = DataStore()..loadData();
  addTearDown(store.dispose);

  if (!empty) {
    await store.commitTracking(
      activities: [
        ReadingActivity(
          id: 'today',
          bookId: 'book',
          bookTitle: 'A book',
          startTime: today,
          endTime: today.add(const Duration(minutes: 30)),
          createdAt: today,
          pages: 12,
        ),
        ReadingActivity(
          id: 'previous-year',
          bookId: 'book',
          bookTitle: 'A book',
          startTime: DateTime(now.year - 1),
          endTime: DateTime(now.year - 1).add(const Duration(minutes: 60)),
          createdAt: DateTime(now.year - 1),
          pages: 24,
        ),
      ],
    );
  }

  if (preferences == null) {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesProvider(await SharedPreferences.getInstance());
    addTearDown(preferences.dispose);
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: preferences),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: StatisticsPage(now: () => now),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [AppTheme.dark, AppTheme.light, AppTheme.eink]) {
    testWidgets('statistics tabs swipe both ways and retain activity scroll in ${theme.brightness}', (tester) async {
      await pumpStatistics(tester, size: const Size(390, 600), theme: theme);
      final pages = find.byType(TabBarView);
      final controller = DefaultTabController.of(tester.element(pages));
      expect(controller.index, 0);
      await tester.drag(pages, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(find.text('Days read'), findsNothing);

      final activityScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('statistics-activity-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.ensureVisible(find.text('Filters'));
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Filter dates'), 180, scrollable: activityScroll);
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(activityScroll).position.pixels;
      expect(offset, greaterThan(0));
      await tester.drag(pages, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      expect(find.text('Days read'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Activity'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(tester.state<ScrollableState>(activityScroll).position.pixels, closeTo(offset, 1));
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('activity restores scroll and expansion independently', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 420);
    addTearDown(tester.view.reset);
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final now = DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 12);

    final store = DataStore()..loadData();

    await store.commitTracking(
      activities: [
        ReadingActivity(
          id: 'manual',
          bookId: 'alice',
          bookTitle: 'Alice',
          startTime: now.subtract(const Duration(minutes: 10)),
          endTime: now,
          createdAt: now,
        ),
      ],
    );

    addTearDown(store.dispose);
    final bucket = PageStorageBucket();

    Future<void> openPage(int revision) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: PageStorage(
              bucket: bucket,
              child: Scaffold(
                body: StatisticsActivityTab(key: ValueKey(revision), now: () => now),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    await openPage(0);
    final scrollKey = find.byKey(const PageStorageKey('statistics-activity-scroll'));
    // Mimic the saved zero offset from the web failure. Expansion rows must
    // never read a numeric scroll offset as their boolean state.
    bucket.writeState(tester.element(scrollKey), 0.0);
    await openPage(1);
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(of: scrollKey, matching: find.byType(Scrollable)).first;
    final finished = find.text('books finished');
    await tester.scrollUntilVisible(finished, 120, scrollable: scrollable);
    final totals = find.ancestor(of: finished, matching: find.byType(Wrap)).first;
    final filters = find.ancestor(of: find.text('Filters'), matching: find.byType(Wrap)).first;
    expect(find.text('Log reading'), findsNothing);
    expect(tester.getTopLeft(finished).dx, tester.getTopLeft(filters).dx);
    expect(tester.getTopLeft(totals).dy - tester.getBottomLeft(filters).dy, Spacing.lg + Spacing.sm);
    final bookRow = find.widgetWithText(ExpansionTile, 'Alice');
    await tester.scrollUntilVisible(bookRow, 200, scrollable: scrollable);
    await tester.ensureVisible(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));
    await openPage(2);
    expect(tester.takeException(), isNull);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, closeTo(offset, 1));
    expect(find.text('Goal history'), findsNothing);
    await tester.scrollUntilVisible(bookRow, -200, scrollable: scrollable);
    expect(find.textContaining('10 min'), findsWidgets);
    final tile = tester.widget<ExpansionTile>(bookRow);
    final expandedChild = find.byWidget(tile.children.first);
    await tester.ensureVisible(expandedChild);
    await tester.pumpAndSettle();
    expect(expandedChild.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('page alignment updates statistics with standard margins at $width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      addTearDown(preferences.dispose);
      await pumpStatistics(tester, size: Size(width, 1000), preferences: preferences);
      final period = find.byKey(const ValueKey('statistics-period-week'));
      final margin = width < 840 ? 16.0 : 24.0;
      final custom = width < 600
          ? find.widgetWithIcon(IconButton, Icons.date_range_outlined)
          : find.widgetWithIcon(OutlinedButton, Icons.date_range_outlined);
      Rect controlsBounds() => tester.getRect(period).expandToInclude(tester.getRect(custom));
      final tabs = find.byType(TabBar);

      if (width >= Breakpoints.desktopSmall) {
        final bounds = tester.getRect(tabs);
        expect(bounds.bottom, ComponentSizes.appBarHeight + BorderWidths.thin);
        expect(bounds.left, margin);
        expect(bounds.right, width - margin);
      }

      expect(tester.getRect(period).left, margin);
      expect(controlsBounds().top, tester.getRect(find.byType(TabBar)).bottom + margin);
      expect(tester.getCenter(period).dy, tester.getCenter(custom).dy);
      expect(tester.getRect(custom).right, width - margin);
      preferences.pageAlignment = 'center';
      await tester.pumpAndSettle();
      final centeredMargin = width > 1168 ? (width - 1120) / 2 : margin;
      if (width >= Breakpoints.desktopSmall) {
        expect(tester.getRect(tabs).left, centeredMargin);
        expect(tester.getRect(tabs).right, width - centeredMargin);
        expect(tester.getRect(tabs).bottom, ComponentSizes.appBarHeight + BorderWidths.thin);
      }

      expect(tester.getRect(period).left, centeredMargin);
      expect(controlsBounds().top, tester.getRect(find.byType(TabBar)).bottom + margin);
      expect(tester.getRect(custom).right, width - centeredMargin);
      preferences.pageAlignment = 'left';
      await tester.pumpAndSettle();
      expect(tester.getRect(period).left, margin);
      expect(tester.getRect(custom).right, width - margin);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('Monday Week shows all seven days at $width', (tester) async {
      await pumpStatistics(tester, size: Size(width, 1000), at: DateTime(2026, 11, 2, 12));
      expect(find.text('Nov 2, 2026 – Nov 8, 2026'), findsOneWidget);

      for (final metric in ['Time', 'Pages']) {
        await tester.tap(find.text(metric));
        await tester.pumpAndSettle();
        final chart = tester.widget<ReadingActivityBarChart>(find.byType(ReadingActivityBarChart));
        expect(chart.activities.length, 7);
        expect(chart.activities.first.date, DateTime(2026, 11, 2));
        expect(chart.activities.last.date, DateTime(2026, 11, 8));
        expect(chart.activities.skip(1).every((day) => day.readingMinutes == 0 && day.pagesRead == 0), isTrue);

        for (var day = 0; day < 7; day++) {
          expect(find.byKey(ValueKey('activity-axis-tick-$day')), findsOneWidget);
        }

        if (width > 600) {
          for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
            expect(find.text(day), findsOneWidget);
          }
        }
      }

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('period and chart controls update totals while broader scopes stay explicit', (tester) async {
    await pumpStatistics(tester, size: const Size(1200, 900));
    expect(find.text('30m'), findsWidgets);
    expect(find.byType(ReadingActivityBarChart), findsOneWidget);
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReadingActivityBarChart>(find.byType(ReadingActivityBarChart)).metric,
      ReadingActivityMetric.pages,
    );
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.byType(StatSectionCard), findsNWidgets(4));
    expect(find.text('Books finished'), findsOneWidget);
    expect(find.text('1.5h'), findsOneWidget);
    final dateButton = find.widgetWithIcon(OutlinedButton, Icons.date_range_outlined);
    expect(tester.getTopLeft(find.text('1.5h')).dy, tester.getBottomLeft(dateButton).dy + Spacing.lg);
    expect(find.textContaining('latest 60 days'), findsNothing);
    expect(find.text('Reading by genre'), findsOneWidget);
    expect(find.textContaining('Lifetime streaks'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom dates do not falsely select Week and cancelling preserves the range', (tester) async {
    await pumpStatistics(tester, size: const Size(1200, 900));
    final dateButton = find.widgetWithIcon(OutlinedButton, Icons.date_range_outlined);
    final material = tester.widget<Material>(find.descendant(of: dateButton, matching: find.byType(Material)));
    expect(material.shape, isA<StadiumBorder>());
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(of: find.byKey(const ValueKey('statistics-period-week')), matching: find.byType(Semantics))
                .first,
          )
          .properties
          .selected,
      isFalse,
    );
    expect(find.text('This week'), findsNothing);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(of: find.byKey(const ValueKey('statistics-period-week')), matching: find.byType(Semantics))
                .first,
          )
          .properties
          .selected,
      isFalse,
    );
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Custom range'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjacent panels match height and activity controls share the header', (tester) async {
    await pumpStatistics(tester, size: const Size(1200, 1000));
    final cards = find.byType(StatSectionCard);
    expect(tester.getSize(cards.at(0)).height, tester.getSize(cards.at(1)).height);
    expect(tester.getSize(cards.at(2)).height, tester.getSize(cards.at(3)).height);
    final header = tester.getRect(find.text('Reading activity'));
    final controls = tester.getRect(find.byType(ChoiceChip).first);
    expect(controls.left, greaterThan(header.right));
    expect(controls.center.dy, greaterThan(header.center.dy));
    expect(controls.center.dy, lessThan(header.bottom + 24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone custom range stays beside periods and empty states omit explanatory copy', (tester) async {
    await pumpStatistics(tester, size: const Size(320, 740), empty: true);
    final week = tester.getRect(find.byKey(const ValueKey('statistics-period-week')));
    final custom = tester.getRect(find.widgetWithIcon(IconButton, Icons.date_range_outlined));
    expect(custom.center.dy, closeTo(week.center.dy, 1));
    expect(custom.right, closeTo(304, 1));
    expect(find.text('Custom range'), findsNothing);
    expect(find.textContaining('Read a book or log reading'), findsNothing);
    expect(find.textContaining('Daily average uses'), findsNothing);
    await tester.tap(find.byTooltip('Custom range'));
    await tester.pumpAndSettle();
    expect(find.text('Select date range'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('presets keep their geometry and the picker shows the selected dates at ${size.width}', (tester) async {
      await pumpStatistics(tester, size: size);
      final keys = ['week', 'month', 'year', 'allTime'];
      Rect buttonRect(String key) => tester.getRect(find.byKey(ValueKey('statistics-period-$key')));
      final original = {for (final key in keys) key: buttonRect(key)};
      final custom = size.width < 600
          ? find.widgetWithIcon(IconButton, Icons.date_range_outlined)
          : find.widgetWithIcon(OutlinedButton, Icons.date_range_outlined);
      final customRect = tester.getRect(custom);
      expect(customRect.right, closeTo(size.width - (size.width < 600 ? 16 : 24), 1));

      for (final period in ['month', 'week']) {
        await tester.tap(find.byKey(ValueKey('statistics-period-$period')));
        await tester.pumpAndSettle();

        for (final key in keys) {
          expect(buttonRect(key), original[key]);
        }

        expect(tester.getRect(custom), customRect);
      }

      await tester.tap(custom);
      await tester.pumpAndSettle();
      final dates = tester.widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog)).initialDateRange!;
      final format = DateFormat.MMMd();
      final label = '${format.format(dates.start)} – ${format.format(dates.end)}';
      await tester.tap(find.text('Apply').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, label).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-period-week')).hitTestable(), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (name: 'small phone', size: const Size(320, 740), scale: 1.0, theme: AppTheme.light),
    (name: 'large text', size: const Size(390, 844), scale: 2.0, theme: AppTheme.dark),
    (name: 'tablet e-ink', size: const Size(768, 1024), scale: 1.3, theme: AppTheme.eink),
    (name: 'desktop', size: const Size(1440, 900), scale: 1.0, theme: AppTheme.dark),
  ]) {
    testWidgets('${scenario.name} keeps populated and empty content usable', (tester) async {
      await pumpStatistics(tester, size: scenario.size, scale: scenario.scale, theme: scenario.theme);
      expect(tester.takeException(), isNull);

      if (scenario.size.width < Breakpoints.desktopSmall) {
        final cards = find.byType(StatSectionCard);
        expect(cards, findsNWidgets(4));

        for (var index = 1; index < 4; index++) {
          final gap = tester.getTopLeft(cards.at(index)).dy - tester.getBottomLeft(cards.at(index - 1)).dy;
          expect(gap, closeTo(Spacing.lg, 0.01));
        }
      }

      await tester.scrollUntilVisible(
        find.text('Reading by genre'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('statistics-overview-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await pumpStatistics(tester, size: scenario.size, scale: scenario.scale, theme: scenario.theme, empty: true);
      expect(find.text('No reading time in this range'), findsOneWidget);
      expect(find.byType(ReadingActivityBarChart), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
