import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:papyrus/models/collection_grid_size.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Shared library and catalog density, measured inside the app shell.
typedef CollectionGridLayout = ({int crossAxisCount, double spacing, double childAspectRatio, double itemWidth});

CollectionGridLayout collectionGridLayout(double width, {double itemWidth = CollectionGridSize.defaultWidth}) {
  final spacing = width >= Breakpoints.tablet ? Spacing.md : Spacing.sm;
  final compactArea = width < Breakpoints.tablet;

  final preferredWidth = compactArea
      ? CollectionGridSize.normalize(itemWidth)
      : math.max(CollectionGridSize.regularMinimum, CollectionGridSize.normalize(itemWidth));

  final desiredColumns = math.max(1, ((width + spacing) / (preferredWidth + spacing)).floor());
  final columns = compactArea ? math.min(4, desiredColumns) : desiredColumns;
  final fittedWidth = math.max(0.0, (width - spacing * (columns - 1)) / columns);
  return (crossAxisCount: columns, spacing: spacing, childAspectRatio: 0.55, itemWidth: fittedWidth);
}

TextStyle? collectionGridTitleStyle(TextTheme theme, {required bool compact}) {
  return compact ? theme.titleSmall?.copyWith(fontSize: theme.labelSmall?.fontSize) : theme.titleSmall;
}

double collectionGridLineHeight(BuildContext context, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: ' ', style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );

  final height = painter.preferredLineHeight;
  painter.dispose();
  return height;
}

const double collectionGridProgressHeight = 3;
const double collectionGridMetadataGap = 2;
double collectionGridMetadataPadding({required bool compact}) => compact ? Spacing.xs : Spacing.sm;

typedef CollectionGridSizeOption = ({int columns, double preferredWidth});

/// Only offer distinct layouts that the current content area can support.
/// Keep the stored width preference so density still adapts across screen sizes.
List<CollectionGridSizeOption> collectionGridSizeOptions(double width) {
  final options = <int, double>{};

  for (double size = CollectionGridSize.minimum; size <= CollectionGridSize.maximum; size += CollectionGridSize.step) {
    final columns = collectionGridLayout(width, itemWidth: size).crossAxisCount;
    final previous = options[columns];

    if (previous == null ||
        (size - CollectionGridSize.defaultWidth).abs() < (previous - CollectionGridSize.defaultWidth).abs()) {
      options[columns] = size;
    }
  }

  return [for (final columns in options.keys.toList()..sort()) (columns: columns, preferredWidth: options[columns]!)];
}
