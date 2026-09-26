import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Privacy and data management settings section for ProfilePage.
class PrivacySettingsSection extends StatelessWidget {
  final bool isDesktop;

  const PrivacySettingsSection({super.key, this.isDesktop = false});

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
        const SettingsSectionHeader(title: 'Privacy & data'),
        SettingsToggleRow(
          label: 'Analytics',
          value: prefs.analyticsOptIn,
          onChanged: (value) => prefs.analyticsOptIn = value,
        ),
        SettingsRow(label: 'Privacy policy', onTap: () {}),
        SettingsRow(label: 'Export all data', onTap: () {}),
        SettingsRow(label: 'Import data', onTap: () {}),
        SettingsRow(label: 'Clear local data', onTap: () {}),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Analytics',
          children: [
            SettingsToggleRow(
              label: 'Send anonymous usage data',
              value: prefs.analyticsOptIn,
              onChanged: (value) => prefs.analyticsOptIn = value,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(
                'Help improve Papyrus by sharing anonymous usage statistics. '
                'No personal data or reading content is collected.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Data management',
          children: [
            SettingsRow(label: 'Export all data', onTap: () {}),
            SettingsRow(label: 'Import data', onTap: () {}),
            SettingsRow(label: 'Clear local data', onTap: () {}),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Legal',
          children: [SettingsRow(label: 'Privacy policy', onTap: () {})],
        ),
      ],
    );
  }
}
