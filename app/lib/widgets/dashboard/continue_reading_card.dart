import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_details/book_progress_bar.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';

/// Card displaying the currently reading book with progress and continue button.
class ContinueReadingCard extends StatelessWidget {
  /// The book currently being read.
  final Book? book;

  /// Called when continue reading is pressed.
  final VoidCallback? onContinue;

  /// Whether to use desktop styling (larger cover, different layout).
  final bool isDesktop;

  const ContinueReadingCard({super.key, this.book, this.onContinue, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (book == null) {
      return _buildEmptyState(context);
    }

    if (isDesktop) {
      return _buildDesktopCard(context);
    }

    return _buildMobileCard(context);
  }

  /// Builds the compact mobile card with cover, info, and play button.
  Widget _buildMobileCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant, width: BorderWidths.thin),
      ),
      child: Row(
        children: [
          _buildCover(context, width: 80, height: 120),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book!.title, style: textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Spacing.xs),
                Text(
                  book!.author,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.sm),
                BookProgressBar(
                  progress: book!.progress,
                  currentPage: book!.currentPage,
                  totalPages: book!.totalPages,
                  showLabel: true,
                  height: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _buildPlayButton(context),
        ],
      ),
    );
  }

  /// Builds the larger desktop card with cover, info, and continue button.
  Widget _buildDesktopCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant, width: BorderWidths.thin),
      ),
      child: Row(
        children: [
          _buildCover(context, width: 120, height: 180),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(book!.title, style: textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Spacing.xs),
                Text(
                  book!.author,
                  style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.md),
                BookProgressBar(
                  progress: book!.progress,
                  currentPage: book!.currentPage,
                  totalPages: book!.totalPages,
                  showLabel: true,
                  height: 4,
                ),
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  onPressed: onContinue ?? () => _navigateToBook(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the empty state when no book is currently being read.
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant, width: BorderWidths.thin),
      ),
      child: EmptyState.compact(
        icon: Icons.menu_book_outlined,
        title: 'No book in progress',
        subtitle: 'Start reading from your library',
        action: EmptyStateAction(label: 'Browse library', onPressed: () => context.go('/library')),
      ),
    );
  }

  /// Builds the book cover image with rounded corners.
  Widget _buildCover(BuildContext context, {required double width, required double height}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: CoverImage(
        bookId: book?.id,
        imageUrl: book?.coverURL,
        mediaId: book?.coverMediaId,
        placeholder: _buildCoverPlaceholder(context),
      ),
    );
  }

  /// Builds a placeholder icon when no cover image is available.
  Widget _buildCoverPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(child: Icon(Icons.menu_book, size: 32, color: colorScheme.onSurfaceVariant));
  }

  /// Builds the circular play button for mobile layout.
  Widget _buildPlayButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 48,
      height: 48,
      child: FilledButton(
        onPressed: onContinue ?? () => _navigateToBook(context),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
        ),
        child: Icon(Icons.play_arrow, color: colorScheme.onPrimary),
      ),
    );
  }

  void _navigateToBook(BuildContext context) {
    if (book != null) {
      context.push('/library/details/${book!.id}');
    }
  }
}
