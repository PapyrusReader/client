import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

class CardShadow {
  CardShadow._();

  static ShapeDecoration decoration(BuildContext context) {
    final cardTheme = CardTheme.of(context);

    return ShapeDecoration(
      shape: cardTheme.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      shadows: shadows(context),
    );
  }

  static List<BoxShadow>? shadows(BuildContext context) {
    if ((CardTheme.of(context).elevation ?? AppElevation.level1) <= 0) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;

    return [
      BoxShadow(
        color: (colorScheme.brightness == Brightness.dark ? colorScheme.outline : colorScheme.shadow).withValues(
          alpha: 0.24,
        ),
        blurRadius: 3,
        offset: Offset.zero,
      ),
    ];
  }
}
