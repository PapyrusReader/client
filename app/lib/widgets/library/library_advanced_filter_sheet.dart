import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/library_filter_options.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/utils/book_language.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/library/library_filter_fields.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

class LibraryAdvancedFilterSheet extends StatefulWidget {
  final LibraryProvider libraryProvider;
  final DataStore dataStore;
  final ScrollController scrollController;
  final List<Book>? sourceBooks;
  final LibraryFilterOptions? filterOptions;

  const LibraryAdvancedFilterSheet({
    super.key,
    required this.libraryProvider,
    required this.dataStore,
    required this.scrollController,
    this.sourceBooks,
    this.filterOptions,
  });

  static Future<LibraryFilters?> show(
    BuildContext context, {
    required LibraryProvider libraryProvider,
    required DataStore dataStore,
    List<Book>? sourceBooks,
    LibraryFilterOptions? filterOptions,
  }) {
    return showModalBottomSheet<LibraryFilters>(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.55,
          maxChildSize: 1,
          snap: true,
          snapSizes: const [0.55, 0.85, 1],
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
                child: LibraryAdvancedFilterSheet(
                  libraryProvider: libraryProvider,
                  dataStore: dataStore,
                  scrollController: scrollController,
                  sourceBooks: sourceBooks,
                  filterOptions: filterOptions,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<LibraryAdvancedFilterSheet> createState() => _LibraryAdvancedFilterSheetState();
}

class _LibraryAdvancedFilterSheetState extends State<LibraryAdvancedFilterSheet> {
  late LibraryFilters _draft = widget.libraryProvider.filters;
  late final List<Book> _sourceBooks = widget.sourceBooks ?? widget.dataStore.books;
  late final LibraryFilterOptions _options =
      widget.filterOptions ??
      (widget.sourceBooks == null
          ? LibraryFilterOptions.fromDataStore(widget.dataStore)
          : LibraryFilterOptions.fromDataStore(widget.dataStore, books: _sourceBooks));

  int get _matchingBookCount {
    return widget.libraryProvider.filterBooks(_sourceBooks, dataStore: widget.dataStore, filters: _draft).length;
  }

  void _updateDraft(LibraryFilters filters) {
    setState(() => _draft = filters);
  }

  void _resetDraft() {
    _updateDraft(LibraryFilters());
  }

  void _applyDraft() {
    Navigator.of(context).pop(_draft);
  }

  List<LibraryFilterOption<T>> _withSelectedOptions<T>(
    List<LibraryFilterOption<T>> options,
    Set<T> selectedValues,
    String Function(T value) labelForValue,
  ) {
    return [
      ...options,
      for (final value in selectedValues)
        if (!options.any((option) => option.value == value))
          LibraryFilterOption(value: value, label: labelForValue(value)),
    ];
  }

  String _authorLabel(String value) {
    for (final book in widget.dataStore.books) {
      for (final author in [book.author, ...book.coAuthors]) {
        if (author.trim().toLowerCase() == value) return author.trim();
      }
    }
    return 'Unknown author ($value)';
  }

  String _languageLabel(String value) {
    for (final book in widget.dataStore.books) {
      if (normalizeBookLanguage(book.language) == value) return bookLanguageLabel(book.language ?? value);
    }
    final label = bookLanguageLabel(value);
    return label == value ? 'Unknown language ($value)' : label;
  }

  String _bookFieldLabel(String value, String? Function(Book book) field, String fieldName) {
    for (final book in widget.dataStore.books) {
      final label = field(book)?.trim();
      if (label != null && label.toLowerCase() == value) return label;
    }
    return 'Unknown $fieldName ($value)';
  }

  String _shelfLabel(String value) {
    for (final shelf in widget.dataStore.shelves) {
      if (shelf.id == value) return shelf.name;
    }
    return 'Unknown shelf ($value)';
  }

  String _topicLabel(String value) {
    for (final topic in widget.dataStore.tags) {
      if (topic.id == value) return topic.name;
    }
    return 'Unknown topic ($value)';
  }

  @override
  Widget build(BuildContext context) {
    final authorOptions = _withSelectedOptions(_options.authors, _draft.authors, _authorLabel);
    final languageOptions = _withSelectedOptions(_options.languages, _draft.languages, _languageLabel);
    final publisherOptions = _withSelectedOptions(
      _options.publishers,
      _draft.publishers,
      (value) => _bookFieldLabel(value, (book) => book.publisher, 'publisher'),
    );
    final formatOptions = _withSelectedOptions(
      _options.formats,
      _draft.formats,
      (value) => _bookFieldLabel(value, (book) => book.formatLabel, 'format'),
    );
    final seriesOptions = _withSelectedOptions(
      _options.series,
      _draft.seriesNames,
      (value) => _bookFieldLabel(value, (book) => book.seriesName, 'series'),
    );
    final shelfOptions = _withSelectedOptions(_options.shelves, _draft.shelfIds, _shelfLabel);
    final topicOptions = _withSelectedOptions(_options.topics, _draft.topicIds, _topicLabel);
    final readingStatusOptions = _withSelectedOptions(
      _options.readingStatuses,
      _draft.statuses,
      (status) => status.label,
    );
    final availableRatings = {..._options.ratings, ..._draft.ratings}.toList()..sort();
    final showUnrated = _options.hasUnrated || _draft.includeUnrated;
    final hasMetadataOptions =
        authorOptions.isNotEmpty ||
        languageOptions.isNotEmpty ||
        formatOptions.isNotEmpty ||
        publisherOptions.isNotEmpty ||
        seriesOptions.isNotEmpty;
    final hasOrganizationOptions = shelfOptions.isNotEmpty || topicOptions.isNotEmpty;
    final hasRatingOptions = availableRatings.isNotEmpty || showUnrated;

    return Column(
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasMetadataOptions) ...[
                  const _SectionHeader(title: 'Metadata'),
                  if (authorOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Authors',
                      options: authorOptions,
                      selectedValues: _draft.authors,
                      onChanged: (values) => _updateDraft(_draft.copyWith(authors: values)),
                    ),
                  if (languageOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Languages',
                      options: languageOptions,
                      selectedValues: _draft.languages,
                      onChanged: (values) => _updateDraft(_draft.copyWith(languages: values)),
                    ),
                  if (publisherOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Publishers',
                      options: publisherOptions,
                      selectedValues: _draft.publishers,
                      onChanged: (values) => _updateDraft(_draft.copyWith(publishers: values)),
                    ),
                  if (formatOptions.isNotEmpty)
                    LibrarySmallFacet<String>(
                      label: 'Formats',
                      options: formatOptions,
                      selectedValues: _draft.formats,
                      onChanged: (values) => _updateDraft(_draft.copyWith(formats: values)),
                    ),
                  if (seriesOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Series',
                      options: seriesOptions,
                      selectedValues: _draft.seriesNames,
                      onChanged: (values) => _updateDraft(_draft.copyWith(seriesNames: values)),
                    ),
                ],
                if (hasOrganizationOptions) ...[
                  _SectionHeader(title: 'Organization', dividerBefore: hasMetadataOptions),
                  if (shelfOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Shelves',
                      options: shelfOptions,
                      selectedValues: _draft.shelfIds,
                      onChanged: (values) => _updateDraft(_draft.copyWith(shelfIds: values)),
                    ),
                  if (topicOptions.isNotEmpty)
                    _SearchableFacet<String>(
                      label: 'Topics',
                      options: topicOptions,
                      selectedValues: _draft.topicIds,
                      onChanged: (values) => _updateDraft(_draft.copyWith(topicIds: values)),
                    ),
                ],
                _SectionHeader(title: 'Reading', dividerBefore: hasMetadataOptions || hasOrganizationOptions),
                if (readingStatusOptions.isNotEmpty)
                  LibrarySmallFacet<LibraryReadingStatus>(
                    label: 'Reading status',
                    showSummary: false,
                    options: readingStatusOptions,
                    selectedValues: _draft.statuses,
                    onChanged: (values) => _updateDraft(_draft.copyWith(statuses: values)),
                  ),
                LibraryFavoriteFilterField(
                  value: _draft.favoriteFilter,
                  onChanged: (value) => _updateDraft(_draft.copyWith(favoriteFilter: value)),
                ),
                LibraryProgressFilterField(
                  value: _draft.progressRange,
                  onChanged: (value) => _updateDraft(_draft.copyWith(progressRange: value)),
                ),
                if (hasRatingOptions)
                  LibraryRatingFilterField(
                    ratings: _draft.ratings,
                    includeUnrated: _draft.includeUnrated,
                    availableRatings: availableRatings,
                    showUnrated: showUnrated,
                    onChanged: (ratings, includeUnrated) {
                      _updateDraft(_draft.copyWith(ratings: ratings, includeUnrated: includeUnrated));
                    },
                  ),
                const _SectionHeader(title: 'Dates', dividerBefore: true),
                LibraryDateRangeField(
                  label: 'Publication date',
                  value: _draft.publicationDateRange,
                  onChanged: (value) => _updateDraft(_draft.copyWith(publicationDateRange: value)),
                ),
                LibraryDateRangeField(
                  label: 'Date added',
                  value: _draft.dateAddedRange,
                  onChanged: (value) => _updateDraft(_draft.copyWith(dateAddedRange: value)),
                ),
                LibraryDateRangeField(
                  label: 'Last read',
                  value: _draft.lastReadDateRange,
                  onChanged: (value) => _updateDraft(_draft.copyWith(lastReadDateRange: value)),
                ),
              ],
            ),
          ),
        ),
        _buildActionBar(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BottomSheetHandle(),
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              Text('Advanced filters', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = _matchingBookCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton(onPressed: _resetDraft, child: const Text('Reset')),
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            const SizedBox(width: Spacing.sm),
            FilledButton(onPressed: _applyDraft, child: Text('Show $count ${count == 1 ? 'book' : 'books'}')),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool dividerBefore;

  const _SectionHeader({required this.title, this.dividerBefore = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dividerBefore) ...[
          Divider(height: Spacing.lg, color: colorScheme.outlineVariant),
          const SizedBox(height: Spacing.xs),
        ],
        Padding(
          padding: const EdgeInsets.only(top: Spacing.sm, bottom: 12),
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchableFacet<T> extends StatefulWidget {
  final String label;
  final List<LibraryFilterOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onChanged;

  const _SearchableFacet({
    required this.label,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
  });

  @override
  State<_SearchableFacet<T>> createState() => _SearchableFacetState<T>();
}

class _SearchableFacetState<T> extends State<_SearchableFacet<T>> {
  late final TextEditingController _searchController;
  bool _isExpanded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_synchronizeQuery);
  }

  @override
  void dispose() {
    _searchController.removeListener(_synchronizeQuery);
    _searchController.dispose();
    super.dispose();
  }

  void _synchronizeQuery() {
    if (_query != _searchController.text) {
      setState(() => _query = _searchController.text);
    }
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  void _updateSelection(LibraryFilterOption<T> option, bool isSelected) {
    final values = Set<T>.of(widget.selectedValues);
    if (isSelected) {
      values.add(option.value);
    } else {
      values.remove(option.value);
    }
    widget.onChanged(values);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final inputDecorationTheme = theme.inputDecorationTheme;
    final isEink = isLibraryFilterEinkTheme(theme);
    final borderRadius = BorderRadius.circular(isEink ? AppRadius.none : AppRadius.lg);
    final headerBorderRadius = _isExpanded
        ? BorderRadius.vertical(top: Radius.circular(isEink ? AppRadius.none : AppRadius.lg))
        : borderRadius;
    final selectionSummary = widget.selectedValues.isEmpty ? 'Any' : '${widget.selectedValues.length} selected';
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleOptions = normalizedQuery.isEmpty
        ? widget.options
        : widget.options.where((option) => option.label.toLowerCase().contains(normalizedQuery)).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: isEink ? BorderWidths.einkDefault : BorderWidths.thin,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Semantics(
              button: true,
              expanded: _isExpanded,
              label: '${widget.label}, $selectionSummary',
              onTap: _toggleExpanded,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: headerBorderRadius,
                onTap: _toggleExpanded,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.label, style: theme.textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                selectionSummary,
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isExpanded) ...[
              Divider(height: 1, color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.md, 12, Spacing.md, Spacing.md),
                child: Column(
                  children: [
                    SizedBox(
                      height: TouchTargets.mobileRecommended,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search ${widget.label.toLowerCase()}...',
                          hintStyle: isEink
                              ? inputDecorationTheme.hintStyle
                              : TextStyle(color: colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
                          prefixIconConstraints: const BoxConstraints(minWidth: TouchTargets.mobileMin),
                          filled: true,
                          fillColor: isEink ? inputDecorationTheme.fillColor : colorScheme.surfaceContainerHighest,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: Spacing.md),
                          border: isEink
                              ? inputDecorationTheme.border
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  borderSide: BorderSide.none,
                                ),
                          enabledBorder: isEink
                              ? inputDecorationTheme.enabledBorder
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  borderSide: BorderSide.none,
                                ),
                          focusedBorder: isEink
                              ? inputDecorationTheme.focusedBorder
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  borderSide: BorderSide(color: colorScheme.primary, width: BorderWidths.inputFocused),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    if (visibleOptions.isEmpty)
                      SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            'No matches',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView.separated(
                          shrinkWrap: true,
                          primary: false,
                          padding: EdgeInsets.zero,
                          itemCount: visibleOptions.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant),
                          itemBuilder: (context, index) {
                            final option = visibleOptions[index];
                            final isSelected = widget.selectedValues.contains(option.value);
                            return _FacetOptionRow(
                              label: option.label,
                              isSelected: isSelected,
                              onChanged: (selected) => _updateSelection(option, selected),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FacetOptionRow extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const _FacetOptionRow({required this.label, required this.isSelected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    void toggleSelection() => onChanged(!isSelected);

    return Semantics(
      container: true,
      enabled: true,
      checked: isSelected,
      label: label,
      onTap: toggleSelection,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: toggleSelection,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  ExcludeFocus(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: AppMotionControl(
                          value: isSelected,
                          builder: (focusNode) =>
                              Checkbox(focusNode: focusNode, value: isSelected, onChanged: (_) => toggleSelection()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
