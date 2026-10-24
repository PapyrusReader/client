import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

/// A row widget for displaying a setting with optional value and navigation.
///
/// Supports three variants:
/// - **Navigation**: Label + optional value + chevron
/// - **Toggle**: Label + switch
/// - **Value only**: Label + value (no interaction)
///
/// ## Example
///
/// ```dart
/// // Navigation row
/// SettingsRow(
///   label: 'Theme',
///   value: 'System default',
///   onTap: () => _showThemePicker(),
/// )
///
/// // Toggle row
/// SettingsToggleRow(
///   label: 'E-ink mode',
///   value: isEinkMode,
///   onChanged: (value) => _toggleEinkMode(value),
/// )
///
/// // Value only row
/// SettingsRow(
///   label: 'Version',
///   value: '1.0.0',
///   showChevron: false,
/// )
/// ```
class SettingsRow extends StatelessWidget {
  /// Primary label text.
  final String label;

  /// Optional value text displayed below or to the right of label.
  final String? value;

  /// Optional widget displayed before the label and value content.
  final Widget? leading;

  /// Optional widget displayed after the label and value content.
  final Widget? trailing;

  /// Called when the row is tapped (for navigation rows).
  final VoidCallback? onTap;

  /// Whether to show the trailing chevron.
  final bool showChevron;
  final bool enabled;

  /// Creates a settings row widget.
  const SettingsRow({
    super.key,
    required this.label,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final showsValueAsTrailing = value != null && !showChevron && trailing == null;

    return Semantics(
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            canRequestFocus: enabled,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: TouchTargets.mobileRecommended),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.sm),
                child: Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: Spacing.md)],
                    Expanded(
                      child: switch (showsValueAsTrailing) {
                        true => Text(label, style: textTheme.bodyLarge),
                        false when value != null => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: textTheme.bodyLarge),
                            const SizedBox(height: 2),
                            Text(value!, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        false => Text(label, style: textTheme.bodyLarge),
                      },
                    ),
                    if (trailing != null)
                      trailing!
                    else if (showChevron && onTap != null)
                      Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: IconSizes.medium)
                    else if (showsValueAsTrailing)
                      Expanded(
                        child: Text(
                          value!,
                          textAlign: TextAlign.end,
                          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A toggle setting row with a switch.
class SettingsToggleRow extends StatelessWidget {
  /// Primary label text.
  final String label;

  /// Current toggle value.
  final bool value;

  /// Called when the toggle value changes.
  final ValueChanged<bool>? onChanged;

  /// Creates a settings toggle row widget.
  const SettingsToggleRow({super.key, required this.label, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final enabled = onChanged != null;
    final toggle = enabled ? () => onChanged!(!value) : null;

    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: enabled,
        onTap: toggle,
        child: AppMotionControl(
          value: value,
          enabled: enabled,
          builder: (focusNode) => InkWell(
            hoverColor: Colors.transparent,
            focusNode: focusNode,
            canRequestFocus: enabled,
            onTap: toggle,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: TouchTargets.mobileRecommended),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(
                          color: enabled ? null : Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                    ExcludeSemantics(
                      child: ExcludeFocus(
                        child: IgnorePointer(
                          child: Switch(value: value, onChanged: onChanged),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
