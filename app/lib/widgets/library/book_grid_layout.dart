import 'dart:math' as math;

import 'package:papyrus/models/book_grid_size.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Shared library and catalog density, measured inside the app shell.
typedef BookGridLayout = ({int crossAxisCount, double spacing, double childAspectRatio});

BookGridLayout bookGridLayout(double width, {double itemWidth = BookGridSize.defaultWidth}) {
  final spacing = width >= Breakpoints.tablet ? Spacing.md : Spacing.sm;
  final columns = math.max(1, ((width + spacing) / (BookGridSize.normalize(itemWidth) + spacing)).floor());
  return (crossAxisCount: columns, spacing: spacing, childAspectRatio: 0.55);
}
