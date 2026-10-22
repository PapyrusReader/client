import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/book_list_item.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('BookListItem', () {
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

    Widget buildListItem({
      Book? book,
      bool isFavorite = false,
      VoidCallback? onTap,
      ValueChanged<bool>? onToggleFavorite,
      VoidCallback? onSelectToggle,
      VoidCallback? onAcquisitionTap,
      VoidCallback? onAcquisitionSelectionToggle,
      bool showProgress = true,
      bool isSelectionMode = false,
      bool isSelected = false,
      bool isAcquisitionSelectionMode = false,
      bool isAcquisitionSelected = false,
      AcquisitionJob? acquisitionJob,
      Size screenSize = const Size(400, 800),
    }) {
      return createTestApp(
        child: BookListItem(
          book: book ?? testBook,
          isFavorite: isFavorite,
          onTap: onTap,
          onToggleFavorite: onToggleFavorite,
          onSelectToggle: onSelectToggle,
          onAcquisitionTap: onAcquisitionTap,
          onAcquisitionSelectionToggle: onAcquisitionSelectionToggle,
          showProgress: showProgress,
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          isAcquisitionSelectionMode: isAcquisitionSelectionMode,
          isAcquisitionSelected: isAcquisitionSelected,
          acquisitionJob: acquisitionJob,
        ),
        screenSize: screenSize,
      );
    }

    testWidgets('displays book title', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(find.text('The Hobbit'), findsOneWidget);
    });

    testWidgets('displays book author', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(find.text('J.R.R. Tolkien'), findsOneWidget);
    });

    testWidgets('omits format badge', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(find.text('EPUB'), findsNothing);
    });

    testWidgets('shows progress bar and label when progress > 0', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('hides progress when showProgress is false', (tester) async {
      await tester.pumpWidget(buildListItem(showProgress: false));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('hides progress bar when progress is 0', (tester) async {
      final noProgressBook = testBook.copyWith(currentPosition: 0.0);
      await tester.pumpWidget(buildListItem(book: noProgressBook));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows filled heart icon when favorite', (tester) async {
      await tester.pumpWidget(buildListItem(isFavorite: true));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('shows empty heart icon when not favorite', (tester) async {
      await tester.pumpWidget(buildListItem(isFavorite: false));
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    for (final favorite in [false, true]) {
      testWidgets('heart toggles favorite $favorite without opening the book', (tester) async {
        var taps = 0;
        bool? currentFavorite;

        await tester.pumpWidget(
          buildListItem(
            isFavorite: favorite,
            onTap: () => taps += 1,
            onToggleFavorite: (current) => currentFavorite = current,
          ),
        );

        final heart = find.byTooltip(favorite ? 'Remove from favorites' : 'Add to favorites');
        expect(tester.getSize(heart).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(heart).height, greaterThanOrEqualTo(48));
        await tester.tap(heart);
        expect(currentFavorite, favorite);
        expect(taps, 0);
      });
    }

    for (final theme in [AppTheme.dark, AppTheme.eink]) {
      testWidgets('long titles fit narrow list rows in ${theme.brightness}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final book = testBook.copyWith(
          title: 'SQL Performance Explained Everything Developers Need to Know about SQL Performance',
          author: 'Winand, Markus',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [BookListItem(book: book, isFavorite: false, onToggleFavorite: (_) {})],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(find.text(book.title)).maxLines, 2);
        expect(
          tester.getRect(find.text(book.title)).right,
          lessThanOrEqualTo(tester.getRect(find.byTooltip('Add to favorites')).left),
        );
      });
    }

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildListItem(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      expect(tapped, true);
    });

    testWidgets('linked job does not use ordinary tap or selection callbacks', (tester) async {
      var ordinaryTaps = 0;
      var ordinarySelections = 0;

      await tester.pumpWidget(
        buildListItem(
          onTap: () => ordinaryTaps += 1,
          onSelectToggle: () => ordinarySelections += 1,
          acquisitionJob: _acquisitionJob(),
        ),
      );

      await tester.tap(find.byType(BookListItem));
      await tester.longPress(find.byType(BookListItem));
      expect(ordinaryTaps, 0);
      expect(ordinarySelections, 0);
    });

    testWidgets('linked job does not expose the ordinary desktop context menu', (tester) async {
      await tester.pumpWidget(buildListItem(acquisitionJob: _acquisitionJob(), screenSize: const Size(900, 800)));
      expect(find.byTooltip('More options'), findsNothing);
    });

    testWidgets('linked job routes tap and long press to acquisition callbacks', (tester) async {
      var ordinaryTaps = 0;
      var ordinarySelections = 0;
      var acquisitionTaps = 0;
      var acquisitionSelections = 0;

      await tester.pumpWidget(
        buildListItem(
          onTap: () => ordinaryTaps += 1,
          onSelectToggle: () => ordinarySelections += 1,
          onAcquisitionTap: () => acquisitionTaps += 1,
          onAcquisitionSelectionToggle: () => acquisitionSelections += 1,
          acquisitionJob: _acquisitionJob(),
        ),
      );

      await tester.tap(find.byType(BookListItem));
      await tester.longPress(find.byType(BookListItem));
      expect(acquisitionTaps, 1);
      expect(acquisitionSelections, 1);
      expect(ordinaryTaps, 0);
      expect(ordinarySelections, 0);
    });

    testWidgets('linked job selection state is independent from ordinary selection', (tester) async {
      var acquisitionTaps = 0;
      var acquisitionSelections = 0;

      await tester.pumpWidget(
        buildListItem(
          isSelectionMode: true,
          isSelected: true,
          onAcquisitionTap: () => acquisitionTaps += 1,
          onAcquisitionSelectionToggle: () => acquisitionSelections += 1,
          acquisitionJob: _acquisitionJob(),
        ),
      );

      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.byType(BookListItem));
      expect(acquisitionTaps, 1);
      expect(acquisitionSelections, 0);

      await tester.pumpWidget(
        buildListItem(
          isSelectionMode: false,
          isSelected: false,
          isAcquisitionSelectionMode: true,
          isAcquisitionSelected: true,
          onAcquisitionTap: () => acquisitionTaps += 1,
          onAcquisitionSelectionToggle: () => acquisitionSelections += 1,
          acquisitionJob: _acquisitionJob(),
        ),
      );

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.byType(BookListItem));
      expect(acquisitionTaps, 1);
      expect(acquisitionSelections, 1);
    });

    testWidgets('ordinary selection mode still routes taps to ordinary selection', (tester) async {
      var ordinaryTaps = 0;
      var ordinarySelections = 0;

      await tester.pumpWidget(
        buildListItem(
          onTap: () => ordinaryTaps += 1,
          onSelectToggle: () => ordinarySelections += 1,
          isSelectionMode: true,
          isSelected: true,
        ),
      );

      await tester.tap(find.byType(BookListItem));
      expect(ordinaryTaps, 0);
      expect(ordinarySelections, 1);
    });

    testWidgets('shows placeholder when no cover URL', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('forwards the book id to the cover renderer', (tester) async {
      await tester.pumpWidget(buildListItem());
      expect(tester.widget<CoverImage>(find.byType(CoverImage)).bookId, testBook.id);
    });

    testWidgets('omits physical format label', (tester) async {
      final physicalBook = testBook.copyWith(isPhysical: true);
      await tester.pumpWidget(buildListItem(book: physicalBook));
      expect(find.text('Physical'), findsNothing);
    });

    testWidgets('displays 100% progress for finished book', (tester) async {
      final finishedBook = testBook.copyWith(readingStatus: LibraryReadingStatus.completed, currentPosition: 1.0);
      await tester.pumpWidget(buildListItem(book: finishedBook));
      expect(find.text('100%'), findsOneWidget);
    });
  });
}

AcquisitionJob _acquisitionJob() {
  return const AcquisitionJob(
    id: 'job-1',
    endpointId: 'endpoint-1',
    ruleId: null,
    bookId: 'book-1',
    title: 'The Hobbit',
    status: AcquisitionJobStatus.downloading,
    clientReference: null,
    clientHash: 'hash-1',
    clientState: 'downloading',
    progressBasisPoints: 4200,
    downloadedBytes: 420,
    totalBytes: 1000,
    downloadSpeedBytesPerSecond: null,
    etaSeconds: null,
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
