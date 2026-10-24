import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// A horizontal divider with centered title text.
class TitledDivider extends StatelessWidget {
  /// The title text to display in the center
  final String title;

  /// Vertical padding around the divider
  final double? verticalPadding;

  const TitledDivider({super.key, required this.title, this.verticalPadding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = verticalPadding ?? Spacing.lg;

    Widget line(EdgeInsets padding) => ConstrainedBox(
      constraints: const BoxConstraints(minWidth: Spacing.xl),
      child: Padding(
        padding: padding,
        child: Divider(thickness: 1.5, color: theme.colorScheme.outlineVariant),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth(), 2: FlexColumnWidth()},
        children: [
          TableRow(
            children: [
              line(const EdgeInsets.only(right: Spacing.md)),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              line(const EdgeInsets.only(left: Spacing.md)),
            ],
          ),
        ],
      ),
    );
  }
}
