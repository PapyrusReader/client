import 'package:flutter/material.dart';
import 'package:papyrus/models/collection_grid_size.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';

/// Fills library preview tiles and adapts missing-cover artwork to the tile.
class CollectionCoverPreview extends StatelessWidget {
  const CollectionCoverPreview({
    super.key,
    required this.bookId,
    required this.title,
    this.imageUrl,
    this.mediaId,
    this.reserveOverlaySpace = false,
  });

  final String bookId;
  final String title;
  final String? imageUrl;
  final String? mediaId;
  final bool reserveOverlaySpace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final placeholderStyle = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant.withValues(alpha: 0.7));

    final placeholder = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < CollectionGridSize.regularMinimum;
        final iconLimit = compact ? IconSizes.medium : IconSizes.display;
        final iconSize = (constraints.biggest.shortestSide * 0.5).clamp(0.0, iconLimit);
        final overlaySpace = reserveOverlaySpace ? Spacing.lg + Spacing.md : 0;
        final showTitle =
            !compact &&
            constraints.maxHeight >=
                iconSize + Spacing.xs + collectionGridLineHeight(context, placeholderStyle) * 2 + overlaySpace * 2;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: iconSize, color: colors.onSurfaceVariant.withValues(alpha: 0.5)),
            if (showTitle) ...[
              const SizedBox(height: Spacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: placeholderStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      },
    );

    return Container(
      constraints: const BoxConstraints.expand(),
      color: colors.surfaceContainerHighest,
      child: CoverImage(
        bookId: bookId,
        imageUrl: imageUrl,
        mediaId: mediaId,
        placeholder: placeholder,
      ),
    );
  }
}
