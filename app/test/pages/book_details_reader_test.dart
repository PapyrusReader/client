import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/book_details/book_details_scroll_view.dart';
import 'package:papyrus/widgets/book_details/book_details_tab_rail.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final (size, textScale) in [
    (const Size(400, 850), 1.0),
    (const Size(320, 568), 1.0),
    (const Size(375, 667), 1.5),
  ]) {
    testWidgets('populated book tabs fit below a long header at $size and text scale $textScale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final book = buildTestBook(
        title: 'SQL Performance Explained Everything Developers Need to Know about SQL Performance',
        author: 'Winand, Markus',
      );

      final createdAt = DateTime(2026, 10, 23);

      final dataStore = DataStore()
        ..loadData(
          books: [book],
          bookmarks: [
            Bookmark(id: 'bookmark', bookId: book.id, position: 0.5, note: 'Saved passage', createdAt: createdAt),
          ],
          annotations: [
            Annotation(
              id: 'annotation',
              bookId: book.id,
              selectedText: 'Highlighted passage',
              location: const BookLocation(pageNumber: 2),
              createdAt: createdAt,
            ),
          ],
          notes: [
            Note(id: 'note', bookId: book.id, title: 'Reading note', content: 'Useful passage', createdAt: createdAt),
          ],
        );

      addTearDown(dataStore.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: dataStore,
          child: MaterialApp(
            theme: textScale == 1 ? AppTheme.dark : AppTheme.eink,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: BookDetailsPage(id: book.id),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
                  NavigationDestination(icon: Icon(Icons.book), label: 'Library'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final rail = find.byType(BookDetailsTabRail, skipOffstage: false);
      final controller = tester.widget<BookDetailsTabRail>(rail).controller!;
      final nestedScroll = tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;

      for (final (index, label, content) in [
        (1, 'bookmarks', 'Saved passage'),
        (2, 'annotations', '"Highlighted passage"'),
        (3, 'notes', 'Reading note'),
      ]) {
        nestedScroll.outerController.jumpTo(0);
        controller.index = index;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final revealOffset = tester.getBottomLeft(rail).dy - navigationTop + 60;

        if (revealOffset > 0) {
          nestedScroll.outerController.jumpTo(revealOffset);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        final railTop = tester.getTopLeft(rail).dy;
        await tester.dragFrom(Offset(size.width / 2, navigationTop - 10), const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(rail).dy, lessThan(railTop));
        expect(find.text(content).hitTestable(), findsOneWidget);
        expect(find.byTooltip('Sort $label').hitTestable(), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'no matching passage');
        await tester.pumpAndSettle();
        expect(find.text('No $label found'), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text(content).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final (size, textScale) in [
    (const Size(400, 850), 1.0),
    (const Size(320, 568), 1.0),
    (const Size(375, 667), 1.5),
  ]) {
    testWidgets('empty book tabs scroll with the header at $size and text scale $textScale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final book = buildTestBook(title: "Alice's Adventures in Wonderland", author: 'Lewis Carroll');
      final dataStore = DataStore()..loadData(books: [book]);
      addTearDown(dataStore.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: dataStore,
          child: MaterialApp(
            theme: textScale == 1 ? AppTheme.dark : AppTheme.eink,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: BookDetailsPage(id: book.id),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
                  NavigationDestination(icon: Icon(Icons.book), label: 'Library'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final rail = find.byType(BookDetailsTabRail, skipOffstage: false);
      final controller = tester.widget<BookDetailsTabRail>(rail).controller!;
      final nestedScroll = tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;

      for (final (index, icon) in [
        (1, Icons.bookmark_outline),
        (2, Icons.highlight_outlined),
        (3, Icons.note_outlined),
      ]) {
        nestedScroll.outerController.jumpTo(0);
        controller.index = index;
        await tester.pumpAndSettle();
        final revealOffset = tester.getBottomLeft(rail).dy - navigationTop + 160;

        if (revealOffset > 0) {
          nestedScroll.outerController.jumpTo(revealOffset);
          await tester.pumpAndSettle();
        }

        expect(tester.getTopLeft(find.byIcon(icon)).dy, tester.getBottomLeft(rail).dy + Spacing.xl);
        final railTop = tester.getTopLeft(rail).dy;
        await tester.dragFrom(Offset(size.width / 2, navigationTop - 20), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(rail).dy, lessThan(railTop));
        expect(tester.getTopLeft(find.byIcon(icon)).dy, tester.getBottomLeft(rail).dy + Spacing.xl);
        await tester.dragFrom(Offset(size.width / 2, navigationTop - 20), const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(rail).dy, tester.getBottomLeft(find.byType(AppBar)).dy);

        if (index == 3) {
          expect(find.text('Add note').hitTestable(), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('book details scroll when the header leaves less room than the tabs need', (tester) async {
    const railKey = ValueKey('details tabs');
    const bodyKey = ValueKey('details body');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: BookDetailsScrollView(
              header: const SizedBox(height: 476, child: Text('Book header')),
              rail: const PreferredSize(
                preferredSize: Size.fromHeight(48),
                child: SizedBox(key: railKey, height: 48, child: Text('Details tabs')),
              ),
              body: ListView(key: bodyKey, children: const [Text('Book content'), SizedBox(height: 1000)]),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragFrom(const Offset(200, 450), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(railKey)).dy, 0);
    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, 48);
    expect(tester.takeException(), isNull);
  });

  for (final (size, textScale) in [
    (const Size(375, 667), 1.0),
    (const Size(320, 568), 1.0),
    (const Size(375, 667), 1.5),
  ]) {
    testWidgets('mobile book details fit $size at text scale $textScale with bottom navigation', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final book = buildTestBook(
        title: "Alice's Adventures in Wonderland",
        author: 'Lewis Carroll',
        isPhysical: true,
        currentPage: 2,
        pageCount: 98,
        description: List.filled(40, 'A long book description.').join('\n\n'),
      );

      final dataStore = DataStore()..loadData(books: [book]);
      addTearDown(dataStore.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: dataStore,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: BookDetailsPage(id: book.id),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
                  NavigationDestination(icon: Icon(Icons.book), label: 'Library'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rail = find.byType(BookDetailsTabRail);
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      await tester.dragFrom(Offset(size.width / 2, navigationTop - 30), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(rail).dy, appBarBottom);
      expect(tester.getBottomLeft(rail).dy, lessThan(navigationTop));
      await tester.drag(rail, const Offset(-800, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet'), findsOneWidget);
      expect(tester.getTopLeft(find.byIcon(Icons.note_outlined)).dy, tester.getBottomLeft(rail).dy + Spacing.xl);
      expect(tester.getTopLeft(find.text('No notes yet')).dy, greaterThanOrEqualTo(tester.getBottomLeft(rail).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile library tabs stay pinned and remain interactive after scrolling', (tester) async {
    tester.view.physicalSize = const Size(424, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final book = buildTestBook(pageCount: 735, description: List.filled(40, 'A long book description.').join('\n\n'));
    final dataStore = DataStore()..loadData(books: [book]);
    addTearDown(dataStore.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: dataStore,
        child: MaterialApp(home: BookDetailsPage(id: book.id)),
      ),
    );

    await tester.pumpAndSettle();
    final rail = find.byType(BookDetailsTabRail);
    final headerBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    expect(find.text('735 pages'), findsNothing);
    expect(tester.getTopLeft(find.byType(CoverImagePreview)).dy - headerBottom, 0);
    expect(tester.getRect(rail).left, 0);
    expect(tester.getRect(rail).width, 424);
    await tester.dragFrom(const Offset(212, 750), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(rail).dy, headerBottom);
    await tester.drag(rail, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes (0)'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    expect(tester.getTopLeft(rail).dy, headerBottom);
    await tester.drag(rail, const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direct in [false, true]) {
    testWidgets('desktop details header goes back from ${direct ? 'a direct link' : 'a pushed page'}', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = buildTestBook(id: 'header-book');
      final dataStore = DataStore()..loadData(books: [book]);
      addTearDown(dataStore.dispose);
      final detailsPath = '/library/details/${book.id}';

      final router = GoRouter(
        initialLocation: direct ? detailsPath : '/previous',
        routes: [
          GoRoute(
            path: '/previous',
            builder: (_, _) => const Scaffold(body: Text('Previous page')),
          ),
          GoRoute(
            path: '/library/books',
            builder: (_, _) => const Scaffold(body: Text('Library books')),
          ),
          GoRoute(
            path: detailsPath,
            builder: (_, _) => Scaffold(body: BookDetailsPage(id: book.id)),
          ),
        ],
      );

      addTearDown(router.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: dataStore,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      if (!direct) {
        router.push(detailsPath);
        await tester.pumpAndSettle();
      }

      expect(find.text('Book details'), findsOneWidget);
      final cover = tester.getRect(find.byType(CoverImagePreview));
      final rail = tester.getRect(find.byType(BookDetailsTabRail));
      expect(rail.top - cover.bottom, 16);
      expect(tester.getTopLeft(find.text('Description')).dx, cover.left);
      expect(tester.getTopLeft(find.text('Description')).dy - rail.bottom, 16);
      final headerPosition = tester.getTopLeft(find.text('Book details'));
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Book details')), headerPosition);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(direct ? 'Library books' : 'Previous page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Start reading explains unsupported formats', (tester) async {
    final book = buildTestBook(id: 'mobi-book', fileFormat: BookFormat.mobi);
    final dataStore = DataStore()..loadData(books: [book]);
    addTearDown(dataStore.dispose);

    final router = GoRouter(
      initialLocation: '/library/details/${book.id}',
      routes: [
        GoRoute(
          path: '/library/details/:bookId',
          builder: (context, state) => BookDetailsPage(id: state.pathParameters['bookId']),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: dataStore,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pump();
    expect(find.text('This book format is not supported yet.'), findsOneWidget);
  });

  testWidgets('Start reading opens the reader route for EPUB books', (tester) async {
    final book = buildTestBook(id: 'epub-book', fileFormat: BookFormat.epub);
    final dataStore = DataStore()..loadData(books: [book]);
    addTearDown(dataStore.dispose);

    final router = GoRouter(
      initialLocation: '/library/details/${book.id}',
      routes: [
        GoRoute(
          path: '/library/details/:bookId',
          builder: (context, state) => BookDetailsPage(id: state.pathParameters['bookId']),
        ),
        GoRoute(
          name: 'BOOK_READER',
          path: '/library/read/:bookId',
          builder: (context, state) => const Scaffold(body: Text('Reader opened')),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: dataStore,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('Reader opened'), findsOneWidget);
  });
}
