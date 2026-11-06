import 'package:flutter/material.dart';

class CardOverlayColors {
  CardOverlayColors._();

  static const background = Color(0x99000000);

  static Color selection(ColorScheme colors) =>
      _foreground(colors.brightness == Brightness.light ? colors.primaryContainer : colors.primary);

  static Color favorite(ColorScheme colors) =>
      _foreground(colors.brightness == Brightness.light ? colors.errorContainer : colors.error);

  static Color _foreground(Color preferred) {
    // A white cover is the brightest possible backing behind the dark scrim.
    // High-contrast and e-ink schemes can supply dark container colors.
    final brightestBackground = Color.alphaBlend(background, Colors.white);
    final contrast = (preferred.computeLuminance() + 0.05) / (brightestBackground.computeLuminance() + 0.05);

    if (contrast >= 3) {
      return preferred;
    }

    return Colors.white;
  }
}
