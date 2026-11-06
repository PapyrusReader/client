import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/reading_timer_page.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:papyrus/widgets/shared/searchable_book_field.dart';
import 'package:papyrus/widgets/timer/reading_timer_clock.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../timer/timer_test_library.dart';

void main() {
  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final font = File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  });

  final start = DateTime.utc(2026, 11, 3, 12);
  final book = Book(id: 'digital', title: 'A Wizard of Earthsea', author: 'Ursula K. Le Guin', addedAt: start);
  late TimerTestLibrary library;
  late DataStore store;
  late ReadingTimerProvider timer;
  late PreferencesProvider preferences;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesProvider(await SharedPreferences.getInstance());
    library = TimerTestLibrary()..replaceAll([book]);
    store = DataStore(bookRepository: library);
    now = start;
    timer = ReadingTimerProvider(store, now: () => now, tick: false);
    await timer.reload();
  });

  tearDown(() {
    timer.dispose();
    store.dispose();
    preferences.dispose();
    library.trackingRepository.changes.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    double scale = 1,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: timer),
          ChangeNotifierProvider.value(value: preferences),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ReadingTimerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final text = find.text(label);
    final target = text.evaluate().isEmpty ? find.byTooltip(label).last : text.last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> selectBook(WidgetTester tester) async {
    await tester.tap(find.byType(SearchableBookField));
    await tester.pumpAndSettle();
    expect(find.text('Search books'), findsOneWidget);
    await tap(tester, book.title);
  }

  testWidgets('focus preserves setup and the same running timer when opened and closed', (tester) async {
    await pump(tester);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Focus')).onPressed, isNull);
    await selectBook(tester);
    await tap(tester, 'Countdown');
    await tap(tester, '15 min');
    await tap(tester, 'Focus');
    expect(find.byKey(const ValueKey('timer-focus')), findsOneWidget);
    expect(find.byType(SearchableBookField), findsNothing);
    expect(find.text('Mode'), findsNothing);
    expect(find.text('Duration'), findsNothing);
    expect(timer.session, isNull);
    await tap(tester, 'Start');
    final session = timer.session!;
    expect(session.bookId, book.id);
    expect(session.targetSeconds, 900);
    now = now.add(const Duration(seconds: 45));
    await tap(tester, 'Exit focus');
    expect(timer.session, same(session));
    expect(timer.elapsed, const Duration(seconds: 45));
    expect(find.byKey(const ValueKey('timer-focus')), findsNothing);
    await tap(tester, 'Focus');
    expect(timer.session, same(session));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timer-focus')), findsNothing);
    expect(timer.running, isTrue);
  });

  testWidgets('iOS edge swipe exits focus without stopping the timer', (tester) async {
    await pump(
      tester,
      size: const Size(390, 844),
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
    );
    await selectBook(tester);
    await tap(tester, 'Start');
    final session = timer.session!;
    await tap(tester, 'Focus');
    await tester.dragFrom(const Offset(1, 400), const Offset(340, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timer-focus')), findsNothing);
    expect(timer.session, same(session));
    expect(timer.running, isTrue);
  });

  testWidgets('focus opens and closes without transition animations', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Focus');
    final route = ModalRoute.of(tester.element(find.byKey(const ValueKey('timer-focus'))))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    testWidgets('focus toggle keeps its header position at width ${size.width}', (tester) async {
      await pump(tester, size: size);
      await selectBook(tester);
      final enter = tester.getRect(find.widgetWithText(TextButton, 'Focus'));
      await tap(tester, 'Focus');
      final exit = tester.getRect(find.widgetWithText(TextButton, 'Exit focus'));
      expect(exit.right, enter.right);
      expect(exit.center.dy, enter.center.dy);
      expect(exit.height, enter.height);
    });
  }

  testWidgets('mobile timer header changes surface when scrolled and resets at the top', (tester) async {
    final fonts = AppTheme.dark.textTheme.apply(fontFamily: 'Roboto');
    await pump(
      tester,
      size: const Size(390, 600),
      theme: AppTheme.dark.copyWith(
        textTheme: fonts,
        textButtonTheme: TextButtonThemeData(
          style: AppTheme.dark.textButtonTheme.style?.copyWith(textStyle: WidgetStatePropertyAll(fonts.labelLarge)),
        ),
      ),
    );

    final surface = find.descendant(of: find.byType(AppPageToolbar), matching: find.byType(Material)).first;
    final initial = tester.widget<Material>(surface).elevation;
    final header = tester.getRect(find.byType(AppPageToolbar));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(surface).elevation, greaterThan(initial));
    expect(tester.getRect(find.byType(AppPageToolbar)), header);

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(surface).elevation, initial);
  });

  testWidgets('focus actions pause resume and save through the existing session flow', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Start');
    now = now.add(const Duration(minutes: 2));
    await tap(tester, 'Focus');
    await tap(tester, 'Pause');
    expect(timer.running, isFalse);
    await tap(tester, 'Resume');
    now = now.add(const Duration(minutes: 1));
    await tap(tester, 'Finish');
    await tester.enterText(find.byType(TextFormField), '12');
    await tap(tester, 'Save');
    expect(library.trackingRepository.savedSeconds, 180);
    expect(library.trackingRepository.savedPage, 12);
    expect(find.byKey(const ValueKey('timer-focus')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timer-focus')), findsNothing);
    expect(timer.session, isNull);
  });

  testWidgets('remote state changes update focus without toggling its local presentation', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Focus');
    await timer.start(book, targetSeconds: 60);
    await tester.pumpAndSettle();
    expect(find.text('Time remaining'), findsOneWidget);
    now = now.add(const Duration(minutes: 2));
    await timer.reload();
    await tester.pumpAndSettle();
    expect(find.text('Goal reached'), findsOneWidget);
    await timer.discard();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timer-focus')), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  for (final (name, size, scale, theme) in [
    ('desktop-dark', const Size(1440, 900), 1.0, AppTheme.dark),
    ('phone-dark', const Size(390, 844), 1.0, AppTheme.dark),
    ('phone-light', const Size(390, 844), 1.0, AppTheme.light),
    ('phone-eink-large', const Size(320, 700), 2.0, AppTheme.eink),
    ('phone-landscape', const Size(844, 390), 1.0, AppTheme.dark),
  ]) {
    testWidgets('focus $name keeps actions reachable', (tester) async {
      final fonts = theme.textTheme.apply(fontFamily: 'Roboto');

      await pump(
        tester,
        size: size,
        scale: scale,
        theme: theme.copyWith(
          textTheme: fonts,
          textButtonTheme: TextButtonThemeData(
            style: theme.textButtonTheme.style?.copyWith(textStyle: WidgetStatePropertyAll(fonts.labelLarge)),
          ),
        ),
      );

      await selectBook(tester);
      await tap(tester, 'Countdown');
      await tap(tester, 'Start');
      now = now.add(const Duration(minutes: 5));
      await tap(tester, 'Focus');
      expect(find.text('25:00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tap(tester, 'Pause');
      expect(timer.running, isFalse);

      await tap(tester, 'Exit focus');
      expect(find.byKey(const ValueKey('timer-focus')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty library keeps clock visible and start disabled', (tester) async {
    store.replaceBooksFromSync([]);
    await pump(tester);
    expect(find.byType(ReadingTimerClock), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed, isNull);
    expect(find.text('Go to library'), findsOneWidget);
  });

  testWidgets('selects an ebook, pauses, resumes and saves optional page progress', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Start');
    now = start.add(const Duration(minutes: 2, seconds: 15));
    await tap(tester, 'Pause');
    expect(timer.elapsed, const Duration(minutes: 2, seconds: 15));
    expect(tester.widget<ReadingTimerClock>(find.byType(ReadingTimerClock)).progress, 0.25);
    now = now.add(const Duration(minutes: 5));
    await tap(tester, 'Resume');
    now = now.add(const Duration(minutes: 1));
    await tap(tester, 'Finish');
    expect(find.text('Save session'), findsOneWidget);
    expect(library.trackingRepository.saves, 0);
    await tester.enterText(find.byType(TextFormField), '12');
    await tap(tester, 'Save');
    expect(timer.session, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(library.trackingRepository.savedSeconds, 195);
    expect(library.trackingRepository.savedPage, 12);
    expect(library.trackingRepository.saves, 1);
    expect(find.text('Reading session saved'), findsOneWidget);
  });

  testWidgets('countdown drains, caps at zero and can continue without counting the gap', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Countdown');
    await tap(tester, 'Custom');
    await tester.enterText(find.byType(TextFormField), '1');
    await tap(tester, 'Start');
    now = now.add(const Duration(seconds: 30));
    await timer.reload();
    await tester.pumpAndSettle();
    expect(tester.widget<ReadingTimerClock>(find.byType(ReadingTimerClock)).progress, 0.5);
    now = now.add(const Duration(minutes: 10));
    await timer.reload();
    await tester.pumpAndSettle();
    expect(find.text('Goal reached'), findsOneWidget);
    expect(tester.widget<ReadingTimerClock>(find.byType(ReadingTimerClock)).time, Duration.zero);
    await tap(tester, 'Resume');
    now = now.add(const Duration(seconds: 30));
    await tap(tester, 'Finish');
    await tap(tester, 'Save');
    expect(library.trackingRepository.savedSeconds, 90);
  });

  for (final countdown in [false, true]) {
    testWidgets('immediately finishing ${countdown ? 'countdown' : 'stopwatch'} clears it without a prompt', (
      tester,
    ) async {
      await pump(tester);
      await selectBook(tester);

      if (countdown) {
        await tap(tester, 'Countdown');
      }

      await tap(tester, 'Start');
      now = now.add(const Duration(milliseconds: 500));
      await tap(tester, 'Finish');
      expect(timer.session, isNull);
      expect(timer.error, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(library.trackingRepository.saves, 0);
      expect(find.text('Reading session saved'), findsNothing);
    });
  }

  testWidgets('failed save appears only in the dialog and keeps entered progress for retry', (tester) async {
    await timer.start(book);
    now = now.add(const Duration(minutes: 1));
    await timer.pause(finish: true);
    await pump(tester);
    await tap(tester, 'Save');
    await tester.enterText(find.byType(TextFormField), '9');
    library.trackingRepository.failWrite = true;
    await tap(tester, 'Save');
    expect(find.text('Save failed. Try again.', skipOffstage: false), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(timer.session, isNotNull);
    library.trackingRepository.failWrite = false;
    await tap(tester, 'Save');
    expect(timer.session, isNull);
    expect(library.trackingRepository.saves, 1);
    expect(library.trackingRepository.savedSeconds, 60);
    expect(library.trackingRepository.savedPage, 9);
  });

  for (final page in [null, 5, 199]) {
    testWidgets('one-second session offers optional page input $page without range checks', (tester) async {
      final selected = book.copyWith(pageCount: 98, currentPage: 50);
      store.replaceBooksFromSync([selected]);
      await timer.start(selected);
      now = now.add(const Duration(seconds: 1));
      await pump(tester);
      await tap(tester, 'Finish');
      expect(find.text('Save session'), findsOneWidget);

      if (page != null) {
        await tester.enterText(find.byType(TextFormField), '$page');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);

      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('This session is no longer available.', skipOffstage: false), findsNothing);
      }

      expect(timer.session, isNull);
      expect(library.trackingRepository.savedPage, page);
      expect(library.trackingRepository.savedSeconds, 1);
      expect(find.text('Reading session saved'), findsOneWidget);
    });
  }

  testWidgets('invalid custom duration stays editable and cannot start', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Countdown');
    await tap(tester, 'Custom');
    await tester.enterText(find.byType(TextFormField), '');
    await tap(tester, 'Custom');
    await tap(tester, 'Start');
    expect(find.text('Enter 1 to 1,440 minutes.'), findsOneWidget);
    expect(timer.session, isNull);
    await tap(tester, '15 min');
    await tap(tester, 'Start');
    expect(timer.session!.targetSeconds, 900);
  });

  testWidgets('reset requires confirmation and keeps the selected book and duration', (tester) async {
    await pump(tester);
    await selectBook(tester);
    await tap(tester, 'Countdown');
    await tap(tester, '15 min');
    await tap(tester, 'Start');
    now = now.add(const Duration(minutes: 1));
    await tap(tester, 'Reset timer');
    await tap(tester, 'Cancel');
    expect(timer.session, isNotNull);
    await tap(tester, 'Reset timer');
    await tap(tester, 'Reset');
    expect(timer.session, isNull);
    expect(library.trackingRepository.saves, 0);
    expect(find.text(book.title), findsOneWidget);
    expect(tester.widget<ReadingTimerClock>(find.byType(ReadingTimerClock)).time, const Duration(minutes: 15));
    await tap(tester, 'Start');
    expect(timer.session!.bookId, book.id);
    expect(timer.session!.targetSeconds, 900);
  });

  testWidgets('duration appears only for countdown and retains the chosen duration', (tester) async {
    final theme = AppTheme.dark;

    await pump(
      tester,
      size: const Size(390, 1000),
      theme: theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(labelStyle: theme.textTheme.labelLarge!.copyWith(fontFamily: 'Roboto')),
      ),
    );
    await selectBook(tester);
    final clock = tester.getRect(find.byType(ReadingTimerClock));
    expect(find.text('Duration'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).showSelectedIcon, isFalse);
    await tap(tester, 'Countdown');
    expect(find.text('Duration'), findsOneWidget);
    final chips = tester.getRect(find.byType(ChoiceChip).first);
    final custom = tester.getRect(find.widgetWithText(ChoiceChip, 'Custom'));
    final panel = tester.getRect(find.byKey(const ValueKey('reading-session')));
    expect(custom.top, chips.top);
    expect(custom.right, lessThanOrEqualTo(panel.right - 24));
    expect(tester.getRect(find.byType(ReadingTimerClock)), clock);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30 min')).onSelected, isNotNull);
    expect(tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).every((chip) => chip.showCheckmark == false), isTrue);
    await tap(tester, '60 min');
    await tap(tester, 'Stopwatch');
    expect(find.text('Duration'), findsNothing);
    expect(tester.getRect(find.byType(ReadingTimerClock)), clock);
    await tap(tester, 'Countdown');
    expect(tester.widget<ReadingTimerClock>(find.byType(ReadingTimerClock)).time, const Duration(hours: 1));
  });

  for (final countdown in [false, true]) {
    testWidgets('${countdown ? 'countdown' : 'stopwatch'} anchors survive all session states', (tester) async {
      await pump(tester);
      await selectBook(tester);

      if (countdown) {
        await tap(tester, 'Countdown');
        await tap(tester, 'Custom');
        await tester.enterText(find.byType(TextFormField), '2');
      }

      Rect panelRect(Finder finder) =>
          tester.getRect(finder).shift(-tester.getTopLeft(find.byKey(const ValueKey('reading-session'))));

      final clock = panelRect(find.byType(ReadingTimerClock));
      final bookField = panelRect(find.byType(SearchableBookField));
      final primary = panelRect(find.byKey(const ValueKey('timer-primary-action')));

      void expectAnchors() {
        expect(panelRect(find.byType(ReadingTimerClock)), clock);
        expect(panelRect(find.byType(SearchableBookField)), bookField);
        expect(panelRect(find.byKey(const ValueKey('timer-primary-action'))), primary);
      }

      await tap(tester, 'Start');
      expectAnchors();
      now = now.add(const Duration(seconds: 10));
      await tap(tester, 'Pause');
      expectAnchors();
      await tap(tester, 'Resume');
      expectAnchors();

      if (countdown) {
        now = now.add(const Duration(minutes: 3));
        await timer.reload();
        await tester.pumpAndSettle();
        expectAnchors();
        await tap(tester, 'Resume');
        expectAnchors();
      }

      await tap(tester, 'Finish');
      await tap(tester, 'Cancel');
      expectAnchors();
      expect(find.textContaining('read.'), findsNothing);
      expect(find.text('Discard session'), findsNothing);
      expect(bookField.bottom, lessThan(clock.top));
      expect(clock.bottom, lessThan(primary.top));
      expect(primary.bottom, lessThan(panelRect(find.text('Mode')).top));
    });
  }

  testWidgets('changing text scale keeps mode choices visible', (tester) async {
    await pump(tester, size: const Size(390, 1000));
    await selectBook(tester);
    await tap(tester, 'Start');
    await pump(tester, size: const Size(390, 1000), scale: 2, theme: AppTheme.eink);
    final modes = tester.getRect(find.byType(SegmentedButton<bool>));
    expect(modes.height, greaterThan(80));
    expect(modes.contains(tester.getCenter(find.text('Stopwatch'))), isTrue);
    expect(modes.contains(tester.getCenter(find.text('Countdown'))), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timer button ink survives pending writes and state changes', (tester) async {
    final ink = _TrackingInkFactory();
    await pump(tester, theme: AppTheme.dark.copyWith(splashFactory: ink));
    await selectBook(tester);

    for (final label in ['Start', 'Pause', 'Resume', 'Finish']) {
      final gate = Completer<void>();
      library.trackingRepository.writeGate = gate;
      final target = label == 'Finish' ? find.byTooltip(label) : find.text(label);
      final previousCount = ink.features.length;
      await tester.tap(target);
      final ripple = ink.features.last;
      final color = ripple.color;
      await tester.pump(const Duration(milliseconds: 16));
      expect(timer.busy, isTrue);
      expect(ink.features.length, previousCount + 1);
      expect(ink.removed.contains(ripple), isFalse);
      expect(ripple.color, color);
      final primary = tester.widget<FilledButton>(find.byKey(const ValueKey('timer-primary-action')));
      expect(primary.onPressed, isNotNull);
      primary.onPressed!();
      gate.complete();
      await tester.pump(const Duration(milliseconds: 16));
      expect(timer.busy, isFalse);
      expect(ink.features.length, previousCount + 1);
      expect(ink.removed.contains(ripple), isFalse);
      expect(ripple.color, color);
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 1));
    }

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(library.trackingRepository.saves, 0);
  });

  for (final (size, scale) in [
    (const Size(1200, 900), 1.0),
    (const Size(390, 1000), 1.0),
    (const Size(320, 1000), 2.0),
  ]) {
    testWidgets('book selection keeps its height at ${size.width} and text scale $scale', (tester) async {
      final longBook = Book(
        id: 'long',
        title: 'A very long book title that takes several lines in a narrow selection field',
        author: 'An author with a very long name and several additional contributors',
        addedAt: start,
      );
      final untitledAuthor = Book(id: 'short', title: 'Earthsea', author: '', addedAt: start);
      store.replaceBooksFromSync([book, longBook, untitledAuthor]);
      await pump(tester, size: size, scale: scale);
      final field = find.byType(SearchableBookField);
      final height = tester.getSize(field).height;

      for (final selected in [book, longBook, untitledAuthor]) {
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tap(tester, selected.title);
        expect(tester.getSize(field).height, height);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('panel fills page width while controls follow the alignment preference', (tester) async {
    await pump(tester, size: const Size(1600, 1200));
    final panel = find.byKey(const ValueKey('reading-session'));
    final field = find.byType(SearchableBookField);
    final border = tester.getRect(panel);
    final controls = tester.getRect(field);
    expect(border.left, 24);
    expect(border.right, 1576);
    expect(border.bottom, 1176);
    expect(controls.left, border.left + 24);
    expect(controls.width, 472);
    preferences.pageAlignment = 'center';
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), border);
    expect(tester.getSize(field).width, controls.width);
    expect(tester.getCenter(find.byKey(const ValueKey('timer-content'))).dx, border.center.dx);
    expect(tester.getTopLeft(find.text('Recent sessions')).dx, greaterThan(tester.getTopRight(field).dx));
  });

  testWidgets('narrow layout places history after timer settings and scrolls to its bottom', (tester) async {
    await pump(tester, size: const Size(390, 700));
    await tap(tester, 'Countdown');
    expect(
      tester.getTopLeft(find.text('Recent sessions')).dy,
      greaterThan(tester.getBottomLeft(find.text('Custom')).dy),
    );
    await tester.ensureVisible(find.text('No saved sessions yet.'));
    await tester.pumpAndSettle();
    expect(find.text('No saved sessions yet.').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, scale, theme) in [
    ('phone', const Size(390, 844), 1.0, AppTheme.light),
    ('large text e-ink', const Size(320, 700), 2.0, AppTheme.eink),
  ]) {
    testWidgets('$name keeps controls reachable without overflow', (tester) async {
      await pump(tester, size: size, scale: scale, theme: theme);
      await selectBook(tester);
      await tap(tester, 'Countdown');
      await tap(tester, 'Start');
      now = now.add(const Duration(minutes: 1));
      await tap(tester, 'Finish');
      await tap(tester, 'Save');
      expect(library.trackingRepository.saves, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

class _TrackingInkFactory extends InteractiveInkFeatureFactory {
  final features = <InteractiveInkFeature>[];
  final removed = <InteractiveInkFeature>[];

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    late InteractiveInkFeature feature;
    feature = InkRipple.splashFactory.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: () {
        removed.add(feature);
        onRemoved?.call();
      },
    );
    features.add(feature);
    return feature;
  }
}
