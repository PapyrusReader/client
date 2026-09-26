import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Accessibility settings section for ProfilePage.
class AccessibilitySettingsSection extends StatelessWidget {
  final bool isDesktop;

  const AccessibilitySettingsSection({super.key, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Accessibility'),
        SettingsToggleRow(
          label: 'Reduce animations',
          value: prefs.reduceAnimations,
          onChanged: (value) => prefs.reduceAnimations = value,
        ),
        SettingsToggleRow(
          label: 'Dyslexia-friendly font',
          value: prefs.dyslexiaFont,
          onChanged: (value) => prefs.dyslexiaFont = value,
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return SettingsCard(
      children: [
        SettingsToggleRow(
          label: 'Reduce animations',
          value: prefs.reduceAnimations,
          onChanged: (value) => prefs.reduceAnimations = value,
        ),
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm, bottom: Spacing.md),
          child: Text(
            'Minimizes motion effects throughout the app. '
            'Separate from e-ink mode.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        SettingsToggleRow(
          label: 'Dyslexia-friendly font',
          value: prefs.dyslexiaFont,
          onChanged: (value) => prefs.dyslexiaFont = value,
        ),
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm, bottom: Spacing.md),
          child: Text(
            'Use OpenDyslexic font across the app interface.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
