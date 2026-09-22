import 'package:flutter/material.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_details/book_details_action_style.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

enum BookReadingActionState { ready, download, checking, syncing, failed, downloading, unavailable }

/// Action buttons for book details page.
/// Shows Continue Reading (or Update Progress for physical books), Favorite, and Edit buttons.
class BookActionButtons extends StatelessWidget {
  final Book book;
  final VoidCallback? onContinueReading;
  final VoidCallback? onUpdateProgress;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEdit;
  final bool isDesktop;
  final BookReadingActionState readingActionState;

  const BookActionButtons({
    super.key,
    required this.book,
    this.onContinueReading,
    this.onUpdateProgress,
    this.onToggleFavorite,
    this.onEdit,
    this.isDesktop = false,
    this.readingActionState = BookReadingActionState.ready,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionStyle = bookDetailsActionStyle(context);
    final iconStyle = bookDetailsActionStyle(context, iconOnly: true);
    final normalReadingLabel = book.progress > 0
        ? 'Continue'
        : isDesktop
        ? 'Start reading'
        : 'Read';
    final digitalLabel = switch (readingActionState) {
      BookReadingActionState.ready || BookReadingActionState.download => normalReadingLabel,
      BookReadingActionState.checking => 'Checking file…',
      BookReadingActionState.syncing => 'Syncing book…',
      BookReadingActionState.failed => 'Sync failed',
      BookReadingActionState.downloading => 'Downloading…',
      BookReadingActionState.unavailable => 'File unavailable',
    };
    final canUseDigitalAction =
        readingActionState == BookReadingActionState.ready || readingActionState == BookReadingActionState.download;
    final digitalIcon = switch (readingActionState) {
      BookReadingActionState.ready => Icon(book.progress > 0 ? Icons.play_arrow : Icons.menu_book),
      BookReadingActionState.download => const Icon(Icons.download_outlined),
      BookReadingActionState.downloading => const SizedBox.square(
        dimension: 18,
        child: AppCircularProgressIndicator(strokeWidth: 2),
      ),
      BookReadingActionState.checking => const Icon(Icons.hourglass_empty),
      BookReadingActionState.syncing => const Icon(Icons.cloud_sync_outlined),
      BookReadingActionState.failed => const Icon(Icons.cloud_off_outlined),
      BookReadingActionState.unavailable => const Icon(Icons.file_download_off_outlined),
    };

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (book.isPhysical)
          FilledButton.icon(
            style: actionStyle,
            onPressed: onUpdateProgress,
            icon: const Icon(Icons.edit_note),
            label: const Text('Update progress'),
          )
        else
          FilledButton.icon(
            style: actionStyle,
            onPressed: canUseDigitalAction ? onContinueReading : null,
            icon: digitalIcon,
            label: Text(digitalLabel),
          ),
        OutlinedButton(
          onPressed: onToggleFavorite,
          style: iconStyle,
          child: Icon(
            book.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: book.isFavorite ? colorScheme.error : colorScheme.primary,
          ),
        ),
        OutlinedButton(
          onPressed: onEdit,
          style: iconStyle,
          child: Icon(Icons.edit_outlined, color: colorScheme.primary),
        ),
      ],
    );
  }
}
