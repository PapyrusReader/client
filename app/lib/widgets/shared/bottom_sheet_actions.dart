import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Matching sheet actions arranged in a single row on every screen size.
class BottomSheetActions extends StatelessWidget {
  const BottomSheetActions({super.key, required this.primary, this.secondary, this.equalWidths = false});

  final Widget primary;
  final Widget? secondary;

  /// Give longer secondary labels room on compact screens.
  final bool equalWidths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryShape =
        theme.filledButtonTheme.style?.shape ??
        const FilledButton(onPressed: null, child: SizedBox()).defaultStyleOf(context).shape;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
    final enlargedText = MediaQuery.textScalerOf(context).scale(16) > 20;
    final style = ButtonStyle(
      visualDensity: VisualDensity.standard,
      minimumSize: const WidgetStatePropertyAll(Size(80, ComponentSizes.buttonHeightMobile)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: compact ? Spacing.md : Spacing.buttonPaddingHorizontal, vertical: Spacing.sm),
      ),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(style: style.merge(theme.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style.merge(theme.outlinedButtonTheme.style).copyWith(shape: primaryShape),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (secondary != null) ...[
              if (compact) Expanded(child: secondary!) else secondary!,
              SizedBox(width: compact ? Spacing.sm : Spacing.md),
            ],
            if (compact)
              Expanded(flex: secondary == null || enlargedText || equalWidths ? 1 : 2, child: primary)
            else
              primary,
          ],
        ),
      ),
    );
  }
}
