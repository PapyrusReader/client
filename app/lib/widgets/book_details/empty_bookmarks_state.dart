import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';

/// Empty state widget for when a book has no bookmarks.
class EmptyBookmarksState extends StatelessWidget {
  final bool isPhysical;
  final VoidCallback? onAddBookmark;

  const EmptyBookmarksState({super.key, this.isPhysical = false, this.onAddBookmark});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      alignment: Alignment.topCenter,
      icon: Icons.bookmark_outline,
      title: 'No bookmarks yet',
      subtitle: isPhysical
          ? 'Save pages you want to return to later.'
          : 'Bookmarks you create while reading will appear here.',
      action: isPhysical ? EmptyStateAction(onPressed: onAddBookmark, icon: Icons.add, label: 'Add bookmark') : null,
    );
  }
}
