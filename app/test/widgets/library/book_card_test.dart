import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/book_storage_status_controller.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/book_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('BookCard', () {
    late Book testBook;

    setUp(() {
      testBook = Book(
        id: 'book-1',
        title: 'The Hobbit',
        author: 'J.R.R. Tolkien',
        readingStatus: LibraryReadingStatus.inProgress,
        currentPosition: 0.5,
        isFavorite: false,
        fileFormat: BookFormat.epub,
        addedAt: DateTime.now(),
      );
    });

    Widget buildCard({
      Book? book,
      bool isFavorite = false,
      void Function(bool)? onToggleFavorite,
      VoidCallback? onTap,
      VoidCallback? onSelectToggle,
      VoidCallback? onEnterSelectionMode,
      bool showProgress = true,
      bool isSelectionMode = false,
      bool isSelected = false,
      bool compact = false,
      AcquisitionJob? acquisitionJob,
      BookAccountStatus? accountStatus,
      BookDeviceStatus? deviceStatus,
      Size cardSize = const Size(200, 300),
      Size screenSize = const Size(400, 800),
      ThemeData? theme,
      TextScaler textScaler = TextScaler.noScaling,
    }) {
      final card = SizedBox(
        width: cardSize.width,
        height: cardSize.height,
        child: BookCard(
          book: book ?? testBook,
          isFavorite: isFavorite,
          onToggleFavorite: onToggleFavorite,
          onTap: onTap,
          onSelectToggle: onSelectToggle,
          onEnterSelectionMode: onEnterSelectionMode,
          showProgress: showProgress,
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          compact: compact,
          acquisitionJob: acquisitionJob,
          accountStatus: accountStatus,
          deviceStatus: deviceStatus,
        ),
      );

      if (theme == null) {
        return createTestApp(child: card, screenSize: screenSize);
      }

      return MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(size: screenSize, textScaler: textScaler),
          child: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: card),
          ),
        ),
      );
    }

    testWidgets('displays book title', (tester) async {
      await tester.pumpWidget(buildCard());
      // Title appears in both the bottom text and the placeholder cover
      expect(find.text('The Hobbit'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays book author', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('J.R.R. Tolkien'), findsOneWidget);
    });

    testWidgets('compact card uses a single title line and exposes the full title to accessibility', (tester) async {
      final book = testBook.copyWith(title: 'The Hobbit, or There and Back Again');

      await tester.pumpWidget(
        buildCard(book: book, compact: true, cardSize: const Size(82, 150), theme: AppTheme.dark),
      );

      final title = find.text(book.title);
      final titleWidget = tester.widget<Text>(title);
      expect(titleWidget.style?.fontSize, lessThan(AppTheme.dark.textTheme.titleSmall!.fontSize!));
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isTrue);
      expect(tester.getSemantics(title).label, contains(book.title));
      expect(find.text(book.author), findsOneWidget);
    });

    testWidgets('a truncated issue title preserves its issue number', (tester) async {
      final book = testBook.copyWith(title: 'A quarterly publication with a long name #42');

      await tester.pumpWidget(
        buildCard(book: book, compact: true, cardSize: const Size(82, 150), theme: AppTheme.dark),
      );

      final issue = find.textContaining('… #42');
      expect(issue, findsOneWidget);
      expect(tester.getSemantics(issue).label, contains(book.title));
    });

    testWidgets('a regular card reveals its truncated title on hover and keyboard focus', (tester) async {
      final book = testBook.copyWith(title: 'The Hobbit, or There and Back Again');

      await tester.pumpWidget(
        buildCard(
          book: book,
          theme: AppTheme.dark,
          cardSize: const Size(150, 270),
          screenSize: const Size(1200, 800),
          onTap: () {},
        ),
      );

      final gridTitle = find.text(book.title).last;
      expect(tester.widget<Text>(gridTitle).maxLines, 1);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(gridTitle));
      await tester.pumpAndSettle();
      expect(find.text(book.title), findsNWidgets(3));
      await pointer.removePointer();
      await tester.pumpAndSettle();
      expect(find.text(book.title), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text(book.title), findsNWidgets(3));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(book.title), findsNWidgets(2));
    });

    testWidgets('the truncated title tooltip opens and closes without animation in e-ink', (tester) async {
      final book = testBook.copyWith(title: 'The Hobbit, or There and Back Again');

      await tester.pumpWidget(
        buildCard(book: book, compact: true, cardSize: const Size(82, 160), theme: AppTheme.eink, onTap: () {}),
      );

      final title = find.text(book.title);
      final tooltip = find.ancestor(of: title, matching: find.byType(RawTooltip));
      expect(tester.widget<RawTooltip>(tooltip).animationStyle, AnimationStyle.noAnimation);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(title));
      await tester.pump();
      expect(title, findsNWidgets(2));
      await pointer.removePointer();
      await tester.pump();
      expect(title, findsOneWidget);
    });

    testWidgets('displays format badge', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('EPUB'), findsOneWidget);
    });

    testWidgets('shows an accessible icon-only account status', (tester) async {
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(
          buildCard(accountStatus: BookAccountStatus.saved, deviceStatus: BookDeviceStatus.missing),
        );

        expect(find.text('Saved'), findsNothing);
        expect(find.semantics.byPredicate((candidate) => candidate.label.contains('Saved')), findsOneWidget);
        expect(find.byKey(const ValueKey('book-unavailable-tint-book-1')), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('displays physical format label', (tester) async {
      final physicalBook = testBook.copyWith(isPhysical: true);
      await tester.pumpWidget(buildCard(book: physicalBook));
      expect(find.text('Physical'), findsOneWidget);
    });

    testWidgets('compact physical card preserves format and saved status without overlapping badges', (tester) async {
      var opened = false;

      await tester.pumpWidget(
        buildCard(
          book: testBook.copyWith(isPhysical: true),
          compact: true,
          cardSize: const Size(66, 200),
          accountStatus: BookAccountStatus.saved,
          onTap: () => opened = true,
        ),
      );

      expect(find.byTooltip('Physical'), findsOneWidget);
      expect(find.byTooltip('Saved'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('Physical')).overlaps(tester.getRect(find.byTooltip('Saved'))), isFalse);
      expect(find.text('J.R.R. Tolkien'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BookCard));
      expect(opened, isTrue);
    });

    for (final theme in [AppTheme.dark, AppTheme.eink]) {
      for (final physical in [true, false]) {
        for (final width in [66.0, 88.0]) {
          testWidgets('compact format and account icons align at $width, physical $physical, ${theme.brightness}', (
            tester,
          ) async {
            final book = testBook.copyWith(isPhysical: physical);

            await tester.pumpWidget(
              buildCard(
                book: book,
                compact: true,
                cardSize: Size(width, 240),
                accountStatus: BookAccountStatus.saved,
                theme: theme,
                textScaler: const TextScaler.linear(2),
              ),
            );

            final formatIcon = find.byIcon(physical ? Icons.menu_book_outlined : Icons.description_outlined);
            final accountIcon = find.byIcon(Icons.cloud_done_outlined);
            final formatSurface = find.ancestor(of: formatIcon, matching: find.byType(Container)).first;
            final accountSurface = find.ancestor(of: accountIcon, matching: find.byType(Container)).first;
            final formatRect = tester.getRect(formatSurface);
            final accountRect = tester.getRect(accountSurface);
            expect(formatRect.size, accountRect.size);
            expect(tester.getCenter(formatIcon).dy, tester.getCenter(accountIcon).dy);
            expect(tester.getCenter(formatIcon), formatRect.center);
            expect(tester.getCenter(accountIcon), accountRect.center);
            expect(formatRect.bottom, accountRect.bottom);
            expect(formatRect.overlaps(accountRect), isFalse);
            expect(find.byTooltip(book.formatLabel), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('shows progress bar when progress > 0', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('hides progress bar when showProgress is false', (tester) async {
      await tester.pumpWidget(buildCard(showProgress: false));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('hides progress bar when progress is 0', (tester) async {
      final noProgressBook = testBook.copyWith(currentPosition: 0.0);
      await tester.pumpWidget(buildCard(book: noProgressBook));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows compact acquisition progress for a downloading placeholder', (tester) async {
      await tester.pumpWidget(
        buildCard(
          book: testBook.copyWith(currentPosition: 0),
          acquisitionJob: _acquisitionJob(downloadSpeedBytesPerSecond: 1536 * 1024, etaSeconds: 180),
        ),
      );

      expect(find.text('Downloading 50%'), findsOneWidget);
      expect(find.text('1.5 MB/s · 3 min remaining'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    });

    testWidgets('uses shared acquisition status labels', (tester) async {
      await tester.pumpWidget(
        buildCard(
          book: testBook.copyWith(currentPosition: 0),
          acquisitionJob: _acquisitionJob(status: AcquisitionJobStatus.completed),
        ),
      );

      expect(find.text('Finishing import'), findsOneWidget);
      expect(find.text('Downloaded'), findsNothing);
    });

    testWidgets('does not invent acquisition progress', (tester) async {
      await tester.pumpWidget(buildCard(book: testBook, acquisitionJob: _acquisitionJob(progressBasisPoints: null)));
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('hides ordinary desktop menu for linked jobs only', (tester) async {
      await tester.pumpWidget(buildCard(acquisitionJob: _acquisitionJob(), screenSize: const Size(900, 800)));
      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.pumpWidget(buildCard(screenSize: const Size(900, 800)));
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.byTooltip('Select'), findsOneWidget);
      expect(find.semantics.byLabel('More options for The Hobbit'), findsOne);
      expect(find.semantics.byLabel('Select The Hobbit'), findsOne);
    });

    testWidgets('fits a narrow linked card without the format badge', (tester) async {
      await tester.pumpWidget(
        buildCard(acquisitionJob: _acquisitionJob(progressBasisPoints: 4200), cardSize: const Size(150, 300)),
      );

      final status = tester.widget<Text>(find.text('Downloading 42%'));
      expect(find.text('EPUB'), findsNothing);
      expect(status.maxLines, 1);
      expect(status.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a narrow e-ink linked card with a long status', (tester) async {
      await tester.pumpWidget(
        buildCard(
          acquisitionJob: _acquisitionJob(status: AcquisitionJobStatus.importing, progressBasisPoints: null),
          cardSize: const Size(150, 300),
          theme: AppTheme.eink,
        ),
      );

      final status = tester.widget<Text>(find.text('Adding to library'));
      expect(find.text('EPUB'), findsNothing);
      expect(status.maxLines, 1);
      expect(status.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes one selected linked acquisition action', (tester) async {
      final semantics = tester.ensureSemantics();
      var selections = 0;

      try {
        await tester.pumpWidget(
          buildCard(
            acquisitionJob: _acquisitionJob(),
            isSelectionMode: true,
            isSelected: true,
            onSelectToggle: () => selections += 1,
          ),
        );

        final finder = find.byKey(const ValueKey('linked-acquisition-book-card-job-1'));
        final node = tester.getSemantics(finder);

        final interactiveNodes = find.semantics
            .byPredicate((candidate) => candidate.getSemanticsData().hasAction(SemanticsAction.tap))
            .evaluate();

        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(interactiveNodes, hasLength(1));
        tester.semantics.tap(find.semantics.byLabel(node.label));
        expect(selections, 1);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('linked acquisition without callbacks has state but no button action', (tester) async {
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(buildCard(acquisitionJob: _acquisitionJob(), isSelected: true));
        final node = tester.getSemantics(find.byKey(const ValueKey('linked-acquisition-book-card-job-1')));
        expect(node.flagsCollection.isButton, isFalse);
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isFalse);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('linked acquisition selector has its own action and does not open details', (tester) async {
      final semantics = tester.ensureSemantics();
      var details = 0;
      var selections = 0;

      try {
        await tester.pumpWidget(
          buildCard(
            acquisitionJob: _acquisitionJob(status: AcquisitionJobStatus.cancelled),
            onTap: () => details += 1,
            onEnterSelectionMode: () => selections += 1,
            screenSize: const Size(1200, 800),
          ),
        );

        tester.semantics.tap(find.semantics.byLabel('Select The Hobbit'));
        await tester.tap(find.byIcon(Icons.radio_button_unchecked));
        expect(selections, 2);
        expect(details, 0);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('linked acquisition stays hovered over its selection control', (tester) async {
      await tester.pumpWidget(
        buildCard(
          acquisitionJob: _acquisitionJob(status: AcquisitionJobStatus.cancelled),
          onEnterSelectionMode: () {},
          screenSize: const Size(1200, 800),
        ),
      );

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(find.byType(BookCard)));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
      await pointer.moveTo(tester.getCenter(find.byKey(const ValueKey('acquisition-selector-job-1'))));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    });

    testWidgets('linked acquisition hides favorite and exposes only its acquisition action', (tester) async {
      final semantics = tester.ensureSemantics();
      var acquisitionTaps = 0;
      var favoriteTaps = 0;

      try {
        await tester.pumpWidget(
          buildCard(
            acquisitionJob: _acquisitionJob(),
            onTap: () => acquisitionTaps += 1,
            onToggleFavorite: (_) => favoriteTaps += 1,
          ),
        );

        final finder = find.byKey(const ValueKey('linked-acquisition-book-card-job-1'));
        final node = tester.getSemantics(finder);

        final interactiveNodes = find.semantics
            .byPredicate((candidate) => candidate.getSemanticsData().hasAction(SemanticsAction.tap))
            .evaluate();

        expect(find.byIcon(Icons.favorite_border), findsNothing);
        expect(find.byIcon(Icons.favorite), findsNothing);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(interactiveNodes, hasLength(1));
        tester.semantics.tap(find.semantics.byLabel(node.label));
        expect(acquisitionTaps, 1);
        expect(favoriteTaps, 0);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('keyboard focus reveals the original hover controls and activates favorite', (tester) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(790, 590));
      addTearDown(pointer.removePointer);
      var favoriteTaps = 0;
      await tester.pumpWidget(
        buildCard(
          screenSize: const Size(1200, 800),
          onTap: () {},
          onToggleFavorite: (_) => favoriteTaps++,
          onEnterSelectionMode: () {},
        ),
      );
      final favorite = find.byIcon(Icons.favorite_border);
      final visibility = find.ancestor(of: favorite, matching: find.byType(AnimatedOpacity));
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(favoriteTaps, 1);
    });

    testWidgets('keeps the favorite action accessible while visually hidden without mouse hover', (tester) async {
      final semantics = tester.ensureSemantics();
      var favoriteTaps = 0;
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(790, 590));
      addTearDown(pointer.removePointer);
      await tester.pumpWidget(buildCard(onToggleFavorite: (_) => favoriteTaps++));
      expect(find.semantics.byLabel('Add to favorites'), findsOne);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await pointer.moveTo(tester.getCenter(find.byType(BookCard)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      expect(favoriteTaps, 1);
      await pointer.moveTo(const Offset(790, 590));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('keeps a favorited heart visible after the mouse leaves', (tester) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(790, 590));
      addTearDown(pointer.removePointer);
      await tester.pumpWidget(buildCard(isFavorite: true));
      await pointer.moveTo(tester.getCenter(find.byType(BookCard)));
      await tester.pumpAndSettle();
      await pointer.moveTo(const Offset(790, 590));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('shows unfilled heart when not favorite', (tester) async {
      await tester.pumpWidget(buildCard(isFavorite: false));
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('shows filled heart when favorite', (tester) async {
      await tester.pumpWidget(buildCard(isFavorite: true));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('calls onToggleFavorite when favorite button tapped', (tester) async {
      bool? tappedValue;
      await tester.pumpWidget(buildCard(isFavorite: false, onToggleFavorite: (current) => tappedValue = current));

      // Find and tap the favorite button (InkWell wrapping the heart icon)
      final favoriteIcon = find.byIcon(Icons.favorite_border);
      expect(favoriteIcon, findsOneWidget);
      await tester.tap(favoriteIcon);
      await tester.pump();
      expect(tappedValue, false);
    });

    testWidgets('calls onTap when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      expect(tapped, true);
    });

    testWidgets('shows placeholder when no cover URL', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('the missing-cover preview leaves room for card controls at enlarged text', (tester) async {
      await tester.pumpWidget(
        buildCard(
          cardSize: const Size(125, 225),
          theme: AppTheme.eink,
          textScaler: const TextScaler.linear(2),
        ),
      );

      expect(find.byIcon(Icons.menu_book), findsOneWidget);
      expect(find.text(testBook.title), findsOneWidget);
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('forwards the book id and fills the cover frame', (tester) async {
      await tester.pumpWidget(buildCard());
      final cover = tester.widget<CoverImage>(find.byType(CoverImage));
      expect(cover.bookId, testBook.id);
      expect(cover.fit, BoxFit.cover);
    });

    testWidgets('renders Card widget', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.byType(Card), findsOneWidget);
    });
  });
}

AcquisitionJob _acquisitionJob({
  AcquisitionJobStatus status = AcquisitionJobStatus.downloading,
  int? progressBasisPoints = 5000,
  int? downloadSpeedBytesPerSecond = 128,
  int? etaSeconds = 4,
}) {
  return AcquisitionJob(
    id: 'job-1',
    endpointId: 'endpoint-1',
    ruleId: null,
    bookId: 'book-1',
    title: 'The Hobbit',
    status: status,
    clientReference: null,
    clientHash: 'hash-1',
    clientState: 'downloading',
    progressBasisPoints: progressBasisPoints,
    downloadedBytes: 512,
    totalBytes: 1024,
    downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond,
    etaSeconds: etaSeconds,
    selectedFilePath: null,
    retryCount: 0,
    error: null,
    nextPollAt: null,
    createdAt: null,
    updatedAt: null,
    submittedAt: null,
    startedAt: null,
    completedAt: null,
    cancelledAt: null,
  );
}
