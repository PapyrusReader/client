import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:papyrus/models/collection_grid_size.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';

typedef CollectionGridCardMetrics = ({bool compact, double? transferDetailsLineHeight});

class CollectionGrid extends StatelessWidget {
  const CollectionGrid({
    super.key,
    required this.preferredWidth,
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
    this.hasTransferDetails = false,
  });

  final double preferredWidth;
  final EdgeInsets padding;
  final int itemCount;
  final Widget Function(BuildContext context, int index, CollectionGridCardMetrics metrics) itemBuilder;
  final bool hasTransferDetails;

  ({double height, double? transferDetailsLineHeight}) _itemDimensions(
    BuildContext context,
    CollectionGridLayout layout, {
    required bool compact,
    required bool hasTransferDetails,
  }) {
    final textTheme = Theme.of(context).textTheme;
    const compactCoverMinimumHeight = 64.0;
    final bodyLineHeight = collectionGridLineHeight(context, textTheme.bodySmall);
    final titleStyle = collectionGridTitleStyle(textTheme, compact: compact);
    final transferDetailsLineHeight = hasTransferDetails
        ? collectionGridLineHeight(context, textTheme.labelSmall)
        : null;
    final transferDetailsHeight = transferDetailsLineHeight == null
        ? 0
        : transferDetailsLineHeight + collectionGridMetadataGap;
    final metadataPadding = collectionGridMetadataPadding(compact: compact);

    final metadataHeight =
        math.max(collectionGridLineHeight(context, titleStyle), IconSizes.small) +
        bodyLineHeight +
        transferDetailsHeight +
        metadataPadding * 2 +
        collectionGridMetadataGap +
        collectionGridProgressHeight;

    // Keep room for the cover overlays or the larger title placeholder.
    final minimumCoverHeight = compact
        ? compactCoverMinimumHeight
        : IconSizes.display + Spacing.xs + bodyLineHeight * 2;
    final height = math.max(layout.itemWidth / layout.childAspectRatio, minimumCoverHeight + metadataHeight);
    return (height: height, transferDetailsLineHeight: transferDetailsLineHeight);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final layout = collectionGridLayout(width, itemWidth: preferredWidth);
        // Keep the established column count and base height as the horizontal gaps shrink.
        final columnSpacing = layout.spacing * 0.75;
        final itemWidth = (width - columnSpacing * (layout.crossAxisCount - 1)) / layout.crossAxisCount;
        final compact = itemWidth < CollectionGridSize.regularMinimum;
        final dimensions = _itemDimensions(context, layout, compact: compact, hasTransferDetails: hasTransferDetails);
        final metrics = (compact: compact, transferDetailsLineHeight: dimensions.transferDetailsLineHeight);

        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: GridView.builder(
            padding: padding,
            // Flutter 3.41 compatibility; replaced by scrollCacheExtent in 3.42+.
            // ignore: deprecated_member_use
            cacheExtent: 200,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisExtent: dimensions.height,
              crossAxisCount: layout.crossAxisCount,
              mainAxisSpacing: layout.spacing,
              crossAxisSpacing: columnSpacing,
              childAspectRatio: layout.childAspectRatio,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) => itemBuilder(context, index, metrics),
          ),
        );
      },
    );
  }
}
