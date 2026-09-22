import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/pages/book_details_page.dart';
import 'package:papyrus/widgets/book_details/book_cover_image.dart';
import 'package:papyrus/widgets/book_details/book_details_tab_rail.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
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
    expect(tester.getTopLeft(find.byType(CoverImagePreview)).dy - headerBottom, 24);
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
