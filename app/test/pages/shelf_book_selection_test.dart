import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/pages/shelf_contents_page.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/library/book_list_item.dart';
import 'package:papyrus/widgets/library/library_filter_chips.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

class _Repository extends Fake implements BookRepository, LibraryRepository, LibraryMembershipWriter {
  final snapshots = StreamController<LibrarySnapshot>.broadcast();
  final relations = <BookShelfRelation>[];
  final writes = <Set<String>>[];
  Completer<void>? pending;
  Completer<void>? afterSnapshot;
  bool emitOnWrite = true;
  bool fail = false;

  @override
  Stream<LibrarySnapshot> watchLibrary() => snapshots.stream;

  @override
  LibraryMembershipWriter get memberships => this;

  void emit() {
    snapshots.add(
      LibrarySnapshot(
        books: [
          buildTestBook(id: 'one', title: 'First book'),
          buildTestBook(id: 'two', title: 'Second book'),
          buildTestBook(id: 'three', title: 'Third book'),
        ],
        shelves: [buildTestShelf(id: 'shelf', name: 'Weekend reading')],
        bookShelves: List.of(relations),
      ),
    );
  }

  @override
  Future<void> updateMemberships({
    required Set<String> bookIds,
    List<String>? shelfIds,
    List<String>? tagIds,
    Set<String>? previousShelfIds,
    Set<String>? previousTagIds,
    bool additive = false,
  }) async {
    if (additive) {
      expect(shelfIds, ['shelf']);
    } else {
      expect(shelfIds, isEmpty);
      expect(previousShelfIds, {'shelf'});
    }

    writes.add(Set.of(bookIds));
    await pending?.future;

    if (fail) {
      throw StateError('Offline write failed');
    }

    for (final bookId in bookIds) {
      if (additive) {
        relations.add(BookShelfRelation(bookId: bookId, shelfId: 'shelf', addedAt: DateTime.now()));
      } else {
        relations.removeWhere((relation) => relation.bookId == bookId && relation.shelfId == 'shelf');
      }
    }

    if (emitOnWrite) {
      emit();
    }

    await afterSnapshot?.future;
  }
}

void main() {
  late _Repository repository;
  late DataStore store;
  late LibraryProvider library;
  late GoRouter router;

  setUp(() {
    repository = _Repository();
    store = DataStore(bookRepository: repository);
    library = LibraryProvider();
    router = GoRouter(
      initialLocation: '/library/shelves/shelf',
      routes: [
        GoRoute(
          path: '/library/shelves/:shelfId',
          builder: (context, state) => ShelfContentsPage(shelfId: state.pathParameters['shelfId']),
          routes: [
            GoRoute(
              path: 'add-books',
              builder: (context, state) => ShelfContentsPage(
                shelfId: state.pathParameters['shelfId'],
                selectBooks: true,
              ),
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    library.dispose();
    store.dispose();
    await repository.snapshots.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 400,
    double scale = 1,
    bool eink = false,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    repository.emit();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: library),
        ],
        child: MaterialApp.router(
          theme: (eink ? AppTheme.eink : AppTheme.dark).copyWith(platform: platform),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool emptyAction = false, bool desktop = false}) async {
    final add = desktop
        ? find.widgetWithText(FilledButton, 'Add to shelf').first
        : emptyAction
        ? find.text('Add to shelf')
        : find.byTooltip('Add to shelf');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add to Weekend reading'), findsOneWidget);
    expect(find.textContaining(' selected'), findsNothing);
    expect(tester.getCenter(find.byTooltip('Select all')).dy, tester.getCenter(find.byTooltip('Back to shelf')).dy);
    expect(tester.getRect(find.byTooltip('Select all')).bottom, lessThan(tester.getRect(find.byType(TextField)).top));
  }

  for (final viewMode in LibraryViewMode.values) {
    testWidgets('$viewMode picker selects across searches, saves, and returns to shelf', (tester) async {
      library.setViewMode(viewMode);
      library.setSearchQuery('parent search');
      repository.relations.add(BookShelfRelation(bookId: 'three', shelfId: 'shelf', addedAt: DateTime.now()));
      await mount(tester);
      await open(tester);
      expect(find.text('Third book'), findsNothing);
      expect(find.text('Add 0 books'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add 0 books')).onPressed, isNull);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is BookCard && widget.book.id == 'one' || widget is BookListItem && widget.book.id == 'one',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add 1 book'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is BookCard && widget.book.id == 'one' || widget is BookListItem && widget.book.id == 'one',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add 0 books'), findsOneWidget);
      expect(find.byTooltip('Add to shelf'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is BookCard && widget.book.id == 'one' || widget is BookListItem && widget.book.id == 'one',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Second');
      await tester.pumpAndSettle();
      expect(find.text('Add 1 book'), findsOneWidget);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('Add 2 books'), findsOneWidget);
      await tester.tap(find.byTooltip('Deselect all'));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 book'), findsOneWidget);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      repository.pending = Completer<void>();
      await tester.tap(find.text('Add 2 books'));
      await tester.pump();
      expect(find.text('Adding…'), findsOneWidget);
      expect(repository.writes, [
        {'one', 'two'},
      ]);
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/library/shelves/shelf');
      expect(store.getBooksInShelf('shelf').map((book) => book.id).toSet(), {'one', 'two', 'three'});
      expect(library.searchQuery, 'parent search');
      expect(library.selectedCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final snapshotFirst in [true, false]) {
    testWidgets('adding all books never flashes empty content, snapshot first: $snapshotFirst', (tester) async {
      await mount(tester);
      await open(tester);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      repository.emitOnWrite = snapshotFirst;
      repository.afterSnapshot = snapshotFirst ? Completer<void>() : null;
      await tester.tap(find.text('Add 3 books'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Add to Weekend reading'), findsOneWidget);
      expect(find.text('Adding…'), findsOneWidget);
      expect(find.byType(BookCard), findsNWidgets(3));
      expect(find.text('No books to add'), findsNothing);
      expect(find.text('No books in this shelf'), findsNothing);

      if (snapshotFirst) {
        repository.afterSnapshot!.complete();
      } else {
        repository.emit();
      }

      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('No books to add'), findsNothing);
        expect(find.text('No books in this shelf'), findsNothing);
      }

      await tester.pumpAndSettle();
      expect(find.text('Add to Weekend reading'), findsNothing);
      expect(store.getBooksInShelf('shelf').length, 3);
      expect(find.byType(BookCard), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty-state action opens picker and back cancels without writes', (tester) async {
    await mount(tester);
    await open(tester, emptyAction: true);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to shelf'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/library/shelves/shelf');
    expect(repository.writes, isEmpty);
    expect(store.getBooksInShelf('shelf'), isEmpty);
  });

  testWidgets('failed save retains selection for retry', (tester) async {
    await mount(tester);
    await open(tester);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    repository.fail = true;
    await tester.tap(find.text('Add 3 books'));
    await tester.pumpAndSettle();
    expect(find.text('Could not add books to the shelf. Please try again.'), findsOneWidget);
    expect(find.text('Add 3 books'), findsOneWidget);
    expect(store.getBooksInShelf('shelf'), isEmpty);
    repository.fail = false;
    await tester.tap(find.text('Add 3 books'));
    await tester.pumpAndSettle();
    expect(store.getBooksInShelf('shelf').length, 3);
  });

  for (final viewMode in LibraryViewMode.values) {
    for (final (width, scale, eink) in [(400.0, 1.0, false), (320.0, 2.0, true), (1200.0, 2.0, true)]) {
      testWidgets('$viewMode shelf selection keeps header and search stable at $width/$scale', (tester) async {
        library.setViewMode(viewMode);

        for (final id in ['one', 'two', 'three']) {
          repository.relations.add(BookShelfRelation(bookId: id, shelfId: 'shelf', addedAt: DateTime.now()));
        }

        await mount(tester, width: width, scale: scale, eink: eink);
        final selection = tester.element(find.byType(LibraryPage)).read<LibraryProvider>();
        final titleRect = tester.getRect(find.text('Weekend reading'));
        final searchRect = tester.getRect(find.byType(TextField));
        final filterRect = tester.getRect(find.byType(LibraryFilterChips));
        await tester.enterText(find.byType(TextField), 'First');
        await tester.pumpAndSettle();
        final searchState = tester.state(find.byType(TextField));
        expect(find.byTooltip('Select all').hitTestable(), findsNothing);
        selection.enterSelectionMode('one');
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isTrue);
        expect(selection.selectedBookIds, {'one'});
        expect(find.textContaining(' selected'), findsNothing);
        expect(find.byTooltip('Deselect all').hitTestable(), findsOneWidget);

        if (width < 840) {
          expect(
            tester.getRect(find.byTooltip('Deselect all')).right,
            lessThanOrEqualTo(tester.getRect(find.byTooltip('Shelf options')).left),
          );
        }

        expect(tester.getRect(find.text('Weekend reading')), titleRect);
        expect(tester.getRect(find.byType(TextField)), searchRect);
        expect(tester.getRect(find.byType(LibraryFilterChips)), filterRect);
        expect(tester.state(find.byType(TextField)), same(searchState));
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'First');
        expect(find.byTooltip('Remove from shelf'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Second');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Select all'));
        await tester.pumpAndSettle();
        expect(selection.selectedBookIds, {'one', 'two'});
        await tester.tap(find.byTooltip('Deselect all'));
        await tester.pumpAndSettle();
        expect(selection.selectedBookIds, {'one'});
        expect(selection.isSelectionMode, isTrue);
        await tester.tap(find.byTooltip('Exit selection'));
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isFalse);
        expect(selection.selectedBookIds, isEmpty);
        expect(find.byTooltip('Select all').hitTestable(), findsNothing);
        expect(find.byTooltip('Deselect all').hitTestable(), findsNothing);
        expect(find.byTooltip('Back to shelves'), findsOneWidget);
        expect(find.byTooltip('Remove from shelf'), findsNothing);
        expect(tester.getRect(find.text('Weekend reading')), titleRect);
        expect(tester.getRect(find.byType(TextField)), searchRect);
        expect(tester.getRect(find.byType(LibraryFilterChips)), filterRect);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [400.0, 1200.0]) {
    testWidgets('shelf selection removes membership without deleting books at $width', (tester) async {
      for (final id in ['one', 'two']) {
        repository.relations.add(BookShelfRelation(bookId: id, shelfId: 'shelf', addedAt: DateTime.now()));
      }

      repository.relations.add(BookShelfRelation(bookId: 'one', shelfId: 'other', addedAt: DateTime.now()));
      await mount(tester, width: width);
      final selection = tester.element(find.byType(LibraryPage)).read<LibraryProvider>();
      selection.enterSelectionMode('one');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete'), findsNothing);
      expect(find.byTooltip('Remove from shelf'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from shelf'));
      await tester.pumpAndSettle();
      expect(repository.writes, [
        {'one', 'two'},
      ]);
      expect(store.getBooksInShelf('shelf'), isEmpty);
      expect(store.getBooksInShelf('other').single.id, 'one');
      expect(store.books.map((book) => book.id).toSet(), {'one', 'two', 'three'});
      expect(selection.isSelectionMode, isFalse);
      expect(find.text('No books in this shelf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed shelf removal keeps selected books for retry', (tester) async {
    repository.relations.add(BookShelfRelation(bookId: 'one', shelfId: 'shelf', addedAt: DateTime.now()));
    await mount(tester);
    final selection = tester.element(find.byType(LibraryPage)).read<LibraryProvider>();
    selection.enterSelectionMode('one');
    await tester.pumpAndSettle();
    repository.fail = true;
    await tester.tap(find.byTooltip('Remove from shelf'));
    await tester.pumpAndSettle();
    expect(find.text('Could not remove books from the shelf. Please try again.'), findsOneWidget);
    expect(selection.selectedBookIds, {'one'});
    expect(store.getBooksInShelf('shelf').single.id, 'one');
    repository.fail = false;
    await tester.tap(find.byTooltip('Remove from shelf'));
    await tester.pumpAndSettle();
    expect(store.getBooksInShelf('shelf'), isEmpty);
    expect(store.getBook('one'), isNotNull);
  });

  for (final viewMode in LibraryViewMode.values) {
    testWidgets('$viewMode shelf context menu removes only that membership', (tester) async {
      library.setViewMode(viewMode);
      repository.relations.add(BookShelfRelation(bookId: 'one', shelfId: 'shelf', addedAt: DateTime.now()));
      repository.relations.add(BookShelfRelation(bookId: 'one', shelfId: 'other', addedAt: DateTime.now()));
      await mount(tester);

      await tester.longPress(
        find.byWidgetPredicate(
          (widget) =>
              widget is BookCard && widget.book.id == 'one' || widget is BookListItem && widget.book.id == 'one',
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      await tester.ensureVisible(find.text('Remove from shelf'));
      await tester.tap(find.text('Remove from shelf'));
      await tester.pumpAndSettle();
      expect(repository.writes, [
        {'one'},
      ]);
      expect(store.getBooksInShelf('shelf'), isEmpty);
      expect(store.getBooksInShelf('other').single.id, 'one');
      expect(store.getBook('one'), isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final eink in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('desktop shelf and selection headers align at $scale, e-ink $eink', (tester) async {
        await mount(tester, width: 1200, scale: scale, eink: eink, platform: TargetPlatform.macOS);
        final backRect = tester.getRect(find.byIcon(Icons.arrow_back));
        final titleLeft = tester.getTopLeft(find.text('Weekend reading')).dx;
        final titleStyle = tester.widget<Text>(find.text('Weekend reading')).style;
        final searchTop = tester.getTopLeft(find.byType(TextField)).dy;
        await open(tester, desktop: true);
        expect(tester.getRect(find.byIcon(Icons.arrow_back)), backRect);
        expect(tester.getTopLeft(find.text('Add to Weekend reading')).dx, titleLeft);
        expect(tester.widget<Text>(find.text('Add to Weekend reading')).style, titleStyle);
        expect(tester.getTopLeft(find.byType(TextField)).dy, searchTop);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets('selection layout at $width with enlarged e-ink text', (tester) async {
      await mount(tester, width: width, scale: 2, eink: true);
      await open(tester, desktop: width >= 840);
      expect(find.byType(BookCard), findsWidgets);
      expect(find.byType(BookListItem), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('Add 3 books'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all books already in shelf shows no books to add', (tester) async {
    for (final id in ['one', 'two', 'three']) {
      repository.relations.add(BookShelfRelation(bookId: id, shelfId: 'shelf', addedAt: DateTime.now()));
    }

    await mount(tester);
    await open(tester);
    expect(find.text('No books to add'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add 0 books')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
