import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Count badge shared by the desktop sidebar and mobile library drawer.
class NavItemCount extends StatelessWidget {
  const NavItemCount({super.key, required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
    );
  }
}
