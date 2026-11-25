import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

class CollectionGridCard extends StatelessWidget {
  const CollectionGridCard({super.key, this.color, required this.child});

  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final themeShape = CardTheme.of(context).shape;
    var shape = themeShape is OutlinedBorder
        ? themeShape
        : const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)));

    if (shape.side.style == BorderStyle.none) {
      final colors = Theme.of(context).colorScheme;
      final outline = Color.lerp(colors.outlineVariant, colors.outline, 0.10)!;
      shape = shape.copyWith(
        side: BorderSide(color: outline, width: BorderWidths.thin),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      color: color,
      child: child,
    );
  }
}
