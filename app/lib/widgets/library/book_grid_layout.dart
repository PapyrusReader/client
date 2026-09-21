import 'package:papyrus/themes/design_tokens.dart';

/// Shared library and catalog density, measured inside the app shell.
typedef BookGridLayout = ({int crossAxisCount, double spacing, double childAspectRatio});

BookGridLayout bookGridLayout(double width, {bool large = false}) {
  if (width >= Breakpoints.desktopLarge) {
    return (crossAxisCount: large ? 4 : 6, spacing: Spacing.md, childAspectRatio: 0.55);
  }
  if (width >= Breakpoints.desktopSmall) {
    return (crossAxisCount: large ? 3 : 5, spacing: Spacing.md, childAspectRatio: 0.55);
  }
  if (width >= Breakpoints.tablet) {
    return (crossAxisCount: large ? 3 : 4, spacing: Spacing.sm + 4, childAspectRatio: 0.55);
  }
  return (crossAxisCount: 2, spacing: Spacing.sm, childAspectRatio: 0.58);
}
