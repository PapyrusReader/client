import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/persistent_save.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/tag.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/utils/text_utils.dart';
import 'package:papyrus/widgets/input/search_field.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/topics/add_topic_sheet.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

/// Bottom sheet for managing topic assignments for a book or multiple books.
class ManageTopicsSheet extends StatefulWidget {
  /// The book to manage topics for (single-book mode).
  final Book? book;

  /// Book IDs for bulk mode.
  final List<String>? bulkBookIds;

  /// Called when topic assignments change.
  final FutureOr<void> Function(List<String> tagIds)? onSave;

  const ManageTopicsSheet({super.key, this.book, this.bulkBookIds, this.onSave});

  bool get isBulkMode => bulkBookIds != null && bulkBookIds!.isNotEmpty;

  /// Shows the manage topics sheet for a single book.
  static Future<void> show(
    BuildContext context, {
    required Book book,
    FutureOr<void> Function(List<String> tagIds)? onSave,
  }) {
    return showModalBottomSheet(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => ManageTopicsSheet(book: book, onSave: onSave),
    );
  }

  /// Shows the manage topics sheet for multiple books (bulk mode).
  static Future<void> showBulk(
    BuildContext context, {
    required List<String> bookIds,
    FutureOr<void> Function(List<String> tagIds)? onSave,
  }) {
    return showModalBottomSheet(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => ManageTopicsSheet(bulkBookIds: bookIds, onSave: onSave),
    );
  }

  @override
  State<ManageTopicsSheet> createState() => _ManageTopicsSheetState();
}

class _ManageTopicsSheetState extends State<ManageTopicsSheet> with PersistentSave<ManageTopicsSheet> {
  late Set<String> _selectedTagIds;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  EntityRepository<Tag>? _repository;

  @override
  void initState() {
    super.initState();
    _repository = context.read<DataStore>().libraryRepository?.tags;

    if (widget.isBulkMode) {
      _selectedTagIds = {};
    } else {
      final dataStore = context.read<DataStore>();
      _selectedTagIds = dataStore.getTagIdsForBook(widget.book!.id).toSet();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dataStore = context.watch<DataStore>();
    final tags = dataStore.tags;
    final filtered = tags.where((item) => item.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
    final shortViewport = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom < 400;

    Widget buildSheet(ScrollController? scrollController) => AppBottomSheet(
      avoidKeyboard: false,
      expandBody: !mobile && tags.isNotEmpty,
      expandOnScroll: tags.isNotEmpty,
      scrollable: tags.isEmpty,
      contentPadding: EdgeInsets.zero,
      header: Row(
        children: [
          // Book cover or bulk icon
          if (!widget.isBulkMode) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(width: 40, height: 60, child: _buildCover(context)),
            ),
            const SizedBox(width: Spacing.sm + Spacing.xs),
          ],
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isBulkMode
                      ? 'Add topics to ${widget.bulkBookIds!.length} ${maybePluralize(widget.bulkBookIds!.length, "topic")}'
                      : 'Manage topics',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!widget.isBulkMode) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.book!.title,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Create new topic button
          IconButton.filledTonal(
            onPressed: _showCreateTopicSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Create new topic',
          ),
        ],
      ),
      footer: BottomSheetFormActions(
        onCancel: isSaving ? null : () => Navigator.pop(context),
        onSave: isSaving ? null : _onSave,
      ),
      body: tags.isEmpty
          ? _buildEmptyState(context)
          : CustomScrollView(
              controller: scrollController,
              shrinkWrap: mobile,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  sliver: SliverToBoxAdapter(
                    child: SearchField(
                      controller: _searchController,
                      hintText: 'Search topics...',
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: const EmptyState.compact(
                      icon: Icons.search_off,
                      title: 'No topics found',
                      subtitle: 'Try a different search term',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _buildTagTile(context, filtered[index]),
                    ),
                  ),
              ],
            ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: mobile || tags.isEmpty
          ? buildSheet(null)
          : DraggableScrollableSheet(
              initialChildSize: shortViewport
                  ? 0.9
                  : (MediaQuery.sizeOf(context).width < Breakpoints.tablet ? 0.8 : 0.5),
              minChildSize: shortViewport ? 0.85 : 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) => buildSheet(scrollController),
            ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final book = widget.book;

    final placeholder = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.menu_book, color: colorScheme.onSurfaceVariant, size: 20),
    );

    if (book == null) {
      return placeholder;
    }

    return CoverImage(bookId: book.id, imageUrl: book.coverURL, mediaId: book.coverMediaId, placeholder: placeholder);
  }

  Widget _buildEmptyState(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom < 400 ||
        MediaQuery.textScalerOf(context).scale(16) > 20;

    return SizedBox(
      width: double.infinity,
      child: EmptyState(
        iconSize: compact ? 32 : 64,
        padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: compact ? Spacing.sm : Spacing.md),
        icon: Icons.label_outline,
        title: 'No topics yet',
        subtitle: 'Tap + to create a topic',
      ),
    );
  }

  Widget _buildTagTile(BuildContext context, Tag tag) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _selectedTagIds.contains(tag.id);
    final tagColor = tag.color;
    final dataStore = context.read<DataStore>();
    final bookCount = dataStore.getBookCountForTag(tag.id);

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      elevation: 0,
      color: isSelected ? tagColor.withValues(alpha: 0.1) : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: isSelected ? tagColor : colorScheme.outlineVariant, width: isSelected ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => _toggleTag(tag.id),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          child: Row(
            children: [
              // Color dot
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              // Tag info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$bookCount ${bookCount == 1 ? 'book' : 'books'}',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // Checkbox
              AppMotionControl(
                value: isSelected,
                builder: (focusNode) => Checkbox(
                  focusNode: focusNode,
                  value: isSelected,
                  onChanged: (_) => _toggleTag(tag.id),
                  activeColor: tagColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleTag(String tagId) {
    setState(() {
      if (_selectedTagIds.contains(tagId)) {
        _selectedTagIds.remove(tagId);
      } else {
        _selectedTagIds.add(tagId);
      }
    });
  }

  void _showCreateTopicSheet() {
    final dataStore = context.read<DataStore>();
    final repository = _repository;

    AddTopicSheet.show(
      context,
      onSave: (name, description, colorHex) async {
        final now = DateTime.now();

        final newTag = Tag(
          id: const Uuid().v4(),
          name: name,
          colorHex: colorHex,
          description: description,
          createdAt: now,
        );

        await dataStore.addTag(newTag, repository: repository);

        if (!mounted) {
          return;
        }

        // Auto-select the newly created topic
        setState(() {
          _selectedTagIds.add(newTag.id);
        });
      },
    );
  }

  Future<void> _onSave() async {
    final saved = await persist(() => widget.onSave?.call(_selectedTagIds.toList()));

    if (saved && mounted) {
      Navigator.pop(context);
    }
  }
}
