import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// A section header for settings pages.
///
/// Provides consistent styling for section titles.
class SettingsSectionHeader extends StatelessWidget {
  /// Section title text.
  final String title;
  final EdgeInsetsGeometry padding;

  /// Creates a settings section header.
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.md),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A card container for settings sections on desktop.
class SettingsCard extends StatelessWidget {
  /// Card title.
  final String? title;

  /// Child widgets.
  final List<Widget> children;

  /// Creates a settings card widget.
  const SettingsCard({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: Spacing.md),
          ],
          ...children,
        ],
      ),
    );
  }
}
