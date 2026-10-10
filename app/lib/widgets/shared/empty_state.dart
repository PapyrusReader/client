import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// A reusable empty state widget for displaying when no content is available.
///
/// Provides an aligned display with an icon, title, optional subtitle,
/// and optional action button.
class EmptyState extends StatelessWidget {
  /// The icon to display at the top.
  final IconData icon;

  /// The main title text.
  final String title;

  /// Optional subtitle text for additional context.
  final String? subtitle;

  /// Optional action widget (typically a button).
  final Widget? action;

  /// The size of the icon. Defaults to 64.
  final double iconSize;

  /// Space around the message; sheets can use less vertical padding.
  final EdgeInsetsGeometry padding;

  /// Position within the available space. Book-detail tabs can align to the top.
  final AlignmentGeometry alignment;

  final bool _compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconSize = 64,
    this.padding = const EdgeInsets.all(Spacing.xl),
    this.alignment = Alignment.center,
  }) : _compact = false;

  /// The same visual treatment at the smaller scale used by cards and panels.
  const EmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconSize = 40,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.alignment = Alignment.center,
  }) : _compact = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: alignment,
      child: SingleChildScrollView(
        primary: false,
        child: Padding(
          padding: padding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ComponentSizes.emptyStateContentWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                SizedBox(height: _compact ? Spacing.sm : Spacing.md),
                Text(
                  title,
                  style: (_compact ? textTheme.titleMedium : textTheme.titleLarge)?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    subtitle!,
                    style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (action != null) ...[SizedBox(height: _compact ? Spacing.md : Spacing.lg), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Consistent sizing for the primary action in a collection's empty state.
class EmptyStateAction extends StatelessWidget {
  const EmptyStateAction({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, ComponentSizes.buttonHeightMobile),
      fixedSize: Size(MediaQuery.textScalerOf(context).scale(ComponentSizes.emptyStateActionWidth), double.infinity),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.buttonPaddingHorizontal,
        vertical: Spacing.buttonPaddingVertical,
      ),
      visualDensity: VisualDensity.standard,
    );

    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: IconSizes.medium),
            label: Text(label),
          );
  }
}
