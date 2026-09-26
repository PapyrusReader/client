import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Developer options settings section for ProfilePage.
class DeveloperSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const DeveloperSettingsSection({super.key, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Developer options'),
        SettingsRow(label: 'Reload sample data', onTap: () {}),
        SettingsRow(label: 'Reset onboarding', onTap: () {}),
        SettingsRow(label: 'Performance overlay', onTap: () {}),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Debug',
          children: [
            SettingsRow(label: 'Reload sample data', onTap: () {}),
            SettingsRow(label: 'Reset onboarding', onTap: () {}),
            SettingsRow(label: 'Performance overlay', onTap: () {}),
          ],
        ),
      ],
    );
  }
}
