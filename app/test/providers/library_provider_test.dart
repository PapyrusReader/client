import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/providers/enums/library_sort_option.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('LibraryProvider', () {
    late LibraryProvider provider;

    setUp(() {
      provider = LibraryProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    group('initial state', () {
      test('uses the default view, sort, search, and filters', () {
        expect(provider.viewMode, LibraryViewMode.grid);
        expect(provider.sortOption, LibrarySortOption.dateAddedNewest);
        expect(provider.searchQuery, isEmpty);
        expect(provider.filters.isEmpty, isTrue);
        expect(provider.activeFilterCount, 0);
      });
    });

    group('view mode', () {
      test('remembers grid size across providers and shares it with shelf contents', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final preferences = PreferencesProvider(prefs);
        final library = LibraryProvider(preferences: preferences);
        final shelf = LibraryProvider(favoriteDelegate: library);
        final restored = LibraryProvider(preferences: PreferencesProvider(prefs));
        addTearDown(library.dispose);
        addTearDown(shelf.dispose);
        addTearDown(restored.dispose);
        addTearDown(preferences.dispose);

        shelf.setGridItemWidth(240);
        expect(library.gridItemWidth, 240);
        library.setViewMode(LibraryViewMode.list);
        library.resetQuickFilters();
        expect(library.gridItemWidth, 240);
        expect(restored.gridItemWidth, 240);
      });

      test('bounds and snaps grid size, ignoring unchanged values', () {
        var notifications = 0;
        provider.addListener(() => notifications++);
        provider.setGridItemWidth(160);
        expect(notifications, 0);
        provider.setGridItemWidth(173);
        expect(provider.gridItemWidth, 180);
        provider.setGridItemWidth(-1);
        expect(provider.gridItemWidth, 120);
        provider.setGridItemWidth(1000);
        expect(provider.gridItemWidth, 320);
        provider.setGridItemWidth(double.nan);
        expect(provider.gridItemWidth, 160);
      });

      test('sets each view mode explicitly', () {
        provider.setViewMode(LibraryViewMode.list);
        expect(provider.viewMode, LibraryViewMode.list);

        provider.setViewMode(LibraryViewMode.grid);
        expect(provider.viewMode, LibraryViewMode.grid);
      });

      test('does not notify when the view mode is unchanged', () {
        var notifications = 0;
        provider.addListener(() => notifications++);

        provider.setViewMode(LibraryViewMode.grid);

        expect(notifications, 0);
      });
    });

    group('structured filters', () {
      test('category setters update the shared filter model', () {
        provider.setStatusFilters({LibraryReadingStatus.inProgress, LibraryReadingStatus.completed});
        provider.setFavoriteFilter(FavoriteFilter.favorites);
        provider.setAuthorFilters({' J.R.R. Tolkien '});
        provider.setLanguageFilters({'EN'});
        provider.setFormatFilters({' EPUB '});
        provider.setShelfFilters({'shelf-1'});
        provider.setTopicFilters({'topic-1'});

        expect(provider.selectedStatuses, {LibraryReadingStatus.inProgress, LibraryReadingStatus.completed});
        expect(provider.favoriteFilter, FavoriteFilter.favorites);
        expect(provider.selectedAuthors, {'j.r.r. tolkien'});
        expect(provider.selectedLanguages, {'en'});
        expect(provider.selectedFormats, {'epub'});
        expect(provider.selectedShelfIds, {'shelf-1'});
        expect(provider.selectedTopicIds, {'topic-1'});
        expect(provider.activeFilterCount, 7);
      });

      test('applyFilters replaces the entire filter draft with one notification', () {
        var notifications = 0;
        provider.addListener(() => notifications++);
        final filters = LibraryFilters(
          authors: {'frank herbert'},
          statuses: {LibraryReadingStatus.completed},
          ratings: {5},
        );

        provider.applyFilters(filters);

        expect(provider.filters, filters);
        expect(provider.activeFilterCount, 3);
        expect(notifications, 1);
      });

      test('clearFilters clears structured filters without clearing search', () {
        provider.setSearchQuery('dune');
        provider.setStatusFilters({LibraryReadingStatus.completed});
        provider.setFavoriteFilter(FavoriteFilter.notFavorites);

        provider.clearFilters();

        expect(provider.filters.isEmpty, isTrue);
        expect(provider.searchQuery, 'dune');
      });

      test('resetQuickFilters restores filters, sort, and view defaults', () {
        provider.setStatusFilters({LibraryReadingStatus.inProgress});
        provider.setSortOption(LibrarySortOption.titleAZ);
        provider.setViewMode(LibraryViewMode.list);

        provider.resetQuickFilters();

        expect(provider.filters.isEmpty, isTrue);
        expect(provider.sortOption, LibrarySortOption.dateAddedNewest);
        expect(provider.viewMode, LibraryViewMode.grid);
      });
    });

    group('search query', () {
      test('sets and clears plain text search independently', () {
        provider.setStatusFilters({LibraryReadingStatus.inProgress});
        provider.setSearchQuery('tolkien');

        provider.clearSearch();

        expect(provider.searchQuery, isEmpty);
        expect(provider.selectedStatuses, {LibraryReadingStatus.inProgress});
      });

      test('does not notify when the search query is unchanged', () {
        provider.setSearchQuery('test');
        var notifications = 0;
        provider.addListener(() => notifications++);

        provider.setSearchQuery('test');

        expect(notifications, 0);
      });
    });

    group('filterBooks', () {
      test('combines text and structured categories with AND logic', () {
        final books = createTestBooks();
        final dataStore = createTestDataStore(books: books);
        provider.setSearchQuery('tolkien');
        provider.setStatusFilters({LibraryReadingStatus.inProgress});
        provider.setFavoriteFilter(FavoriteFilter.favorites);

        final filtered = provider.filterBooks(books, dataStore: dataStore);

        expect(filtered.map((book) => book.id), ['book-1']);
      });

      test('uses OR logic within the reading-status category', () {
        final books = createTestBooks();
        final dataStore = createTestDataStore(books: books);
        provider.setStatusFilters({LibraryReadingStatus.inProgress, LibraryReadingStatus.completed});

        final filtered = provider.filterBooks(books, dataStore: dataStore);

        expect(filtered.map((book) => book.id), ['book-1', 'book-2', 'book-5']);
      });

      test('can preview a draft without replacing applied filters', () {
        final books = createTestBooks();
        final dataStore = createTestDataStore(books: books);
        provider.setStatusFilters({LibraryReadingStatus.unread});
        final draft = LibraryFilters(favoriteFilter: FavoriteFilter.favorites);

        final preview = provider.filterBooks(books, dataStore: dataStore, filters: draft);

        expect(preview.map((book) => book.id), ['book-1', 'book-4']);
        expect(provider.selectedStatuses, {LibraryReadingStatus.unread});
      });
    });
  });
}
