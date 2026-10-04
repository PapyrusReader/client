import 'dart:math' as math;

import 'package:papyrus/models/book_grid_size.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Shared library and catalog density, measured inside the app shell.
typedef BookGridLayout = ({int crossAxisCount, double spacing, double childAspectRatio, double itemWidth});

BookGridLayout bookGridLayout(double width, {double itemWidth = BookGridSize.defaultWidth}) {
  final spacing = width >= Breakpoints.tablet ? Spacing.md : Spacing.sm;
  final compactArea = width < Breakpoints.tablet;
  final preferredWidth = compactArea
      ? BookGridSize.normalize(itemWidth)
      : math.max(BookGridSize.regularMinimum, BookGridSize.normalize(itemWidth));
  final desiredColumns = math.max(1, ((width + spacing) / (preferredWidth + spacing)).floor());
  final columns = compactArea ? math.min(4, desiredColumns) : desiredColumns;
  final fittedWidth = math.max(0.0, (width - spacing * (columns - 1)) / columns);
  return (crossAxisCount: columns, spacing: spacing, childAspectRatio: 0.55, itemWidth: fittedWidth);
}

typedef BookGridSizeOption = ({int columns, double preferredWidth});

/// Only offer distinct layouts that the current content area can support.
/// Keep the stored width preference so density still adapts across screen sizes.
List<BookGridSizeOption> bookGridSizeOptions(double width) {
  final options = <int, double>{};
  for (double size = BookGridSize.minimum; size <= BookGridSize.maximum; size += BookGridSize.step) {
    final columns = bookGridLayout(width, itemWidth: size).crossAxisCount;
    final previous = options[columns];
    if (previous == null || (size - BookGridSize.defaultWidth).abs() < (previous - BookGridSize.defaultWidth).abs()) {
      options[columns] = size;
    }
  }
  return [for (final columns in options.keys.toList()..sort()) (columns: columns, preferredWidth: options[columns]!)];
}
