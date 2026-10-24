import 'package:flutter/material.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/book_storage_status_controller.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/utils/book_actions.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/acquisition_status_text.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

/// List row for displaying a book with cover thumbnail, title, author,
/// progress and a favorite action.
/// Supports context menu via long press (mobile) or right-click (desktop).
class BookListItem extends StatefulWidget {
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveFromShelf;
  final bool showProgress;
  final bool isFavorite;
  final ValueChanged<bool>? onToggleFavorite;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;
  final AcquisitionJob? acquisitionJob;
  final VoidCallback? onAcquisitionTap;
  final bool isAcquisitionSelectionMode;
  final bool isAcquisitionSelected;
  final VoidCallback? onAcquisitionSelectionToggle;
  final BookDeviceStatus? deviceStatus;

  const BookListItem({
    super.key,
    required this.book,
    this.onTap,
    this.onRemoveFromShelf,
    this.showProgress = true,
    required this.isFavorite,
    this.onToggleFavorite,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectToggle,
    this.acquisitionJob,
    this.onAcquisitionTap,
    this.isAcquisitionSelectionMode = false,
    this.isAcquisitionSelected = false,
    this.onAcquisitionSelectionToggle,
    this.deviceStatus,
  });

  @override
  State<BookListItem> createState() => _BookListItemState();
}

class _BookListItemState extends State<BookListItem> {
  bool get _isDesktop => MediaQuery.of(context).size.width >= Breakpoints.desktopSmall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAcquisition = widget.acquisitionJob != null;
    final inSelection = isAcquisition ? widget.isAcquisitionSelectionMode : widget.isSelectionMode;
    final isSelected = isAcquisition ? widget.isAcquisitionSelected : widget.isSelected;
    final onSelectionToggle = isAcquisition ? widget.onAcquisitionSelectionToggle : widget.onSelectToggle;

    final onTap = switch (isAcquisition) {
      true => switch (inSelection) {
        true => widget.onAcquisitionSelectionToggle,
        false => widget.onAcquisitionTap,
      },
      false when inSelection => widget.onSelectToggle,
      false => widget.onTap,
    };

    final isUnavailable = !isAcquisition && !widget.book.isPhysical && widget.deviceStatus == BookDeviceStatus.missing;

    return GestureDetector(
      onLongPressStart: switch (isAcquisition) {
        true => switch (widget.onAcquisitionSelectionToggle == null) {
          true => null,
          false => (_) => widget.onAcquisitionSelectionToggle!(),
        },
        false when _isDesktop || inSelection => null,
        false => (details) {
          showBookContextMenu(
            context: context,
            book: widget.book,
            position: details.globalPosition,
            onRemoveFromShelf: widget.onRemoveFromShelf,
          );
        },
      },
      child: Material(
        color: switch (inSelection && isSelected) {
          true => colorScheme.primary.withValues(alpha: 0.08),
          false when isUnavailable => colorScheme.surfaceContainerLow,
          false => Colors.transparent,
        },
        child: InkWell(
          onTap: onTap,
          child: Container(
            // The list owns the horizontal page gutter.
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                // Selection checkbox (leading)
                if (inSelection) ...[
                  AppMotionControl(
                    value: isSelected,
                    builder: (focusNode) => Checkbox(
                      focusNode: focusNode,
                      semanticLabel: 'Select ${widget.book.title}',
                      value: isSelected,
                      onChanged: (_) => onSelectionToggle?.call(),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
                // Cover thumbnail
                SizedBox(
                  width: ComponentSizes.bookCoverWidthList,
                  height: ComponentSizes.bookCoverHeightList,
                  child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: _buildCover(context)),
                ),
                const SizedBox(width: Spacing.md),

                // Book info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.book.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        widget.book.author,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.acquisitionJob case final job?) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          acquisitionStatusLabel(job),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: job.requiresAttention ? colorScheme.error : colorScheme.onSurfaceVariant,
                            fontWeight: job.requiresAttention ? FontWeight.w600 : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (acquisitionTransferDetails(job) case final details?) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (job.progress case final progress?) ...[
                          const SizedBox(height: Spacing.xs),
                          AppLinearProgressIndicator(
                            value: progress,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            color: job.requiresAttention ? colorScheme.error : colorScheme.primary,
                            minHeight: 3,
                          ),
                        ],
                      ] else if (widget.showProgress && widget.book.currentPosition > 0) ...[
                        const SizedBox(height: Spacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: AppLinearProgressIndicator(
                                value: widget.book.currentPosition,
                                backgroundColor: colorScheme.surfaceContainerHighest,
                                color: widget.book.readingStatus == LibraryReadingStatus.completed
                                    ? colorScheme.tertiary
                                    : colorScheme.primary,
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              widget.book.progressLabel,
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                if (!inSelection && !isAcquisition)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: Spacing.xs),
                      IconButton(
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(TouchTargets.mobileRecommended),
                        ),
                        onPressed: widget.onToggleFavorite == null
                            ? null
                            : () => widget.onToggleFavorite!(widget.isFavorite),
                        tooltip: widget.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                        isSelected: widget.isFavorite,
                        icon: const Icon(Icons.favorite_border),
                        selectedIcon: const Icon(Icons.favorite),
                        color: widget.isFavorite ? colorScheme.error : colorScheme.onSurfaceVariant,
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        iconSize: IconSizes.action,
                        onPressed: () => showBookContextMenu(
                          context: context,
                          book: widget.book,
                          onRemoveFromShelf: widget.onRemoveFromShelf,
                        ),
                        tooltip: 'More options',
                        style: IconButton.styleFrom(minimumSize: const Size.square(TouchTargets.mobileRecommended)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final cover = CoverImage(
      bookId: widget.book.id,
      imageUrl: widget.book.coverUrl,
      mediaId: widget.book.coverMediaId,
      placeholder: _buildPlaceholder(context),
    );

    if (widget.book.isPhysical || widget.deviceStatus != BookDeviceStatus.missing) {
      return cover;
    }

    return ColorFiltered(
      key: ValueKey('book-unavailable-tint-${widget.book.id}'),
      colorFilter: const ColorFilter.matrix([
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        0.68,
        0,
      ]),
      child: cover,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.menu_book, size: IconSizes.medium, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }
}
