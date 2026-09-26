import 'package:flutter/material.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';

/// About settings section for ProfilePage.
class AboutSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const AboutSettingsSection({super.key, this.isDesktop = false});

  static void showLicenses(BuildContext context) {
    showLicensePage(context: context, applicationName: 'Papyrus', applicationVersion: '1.0.0');
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'About'),
        const SettingsRow(label: 'Version', value: '1.0.0', showChevron: false),
        SettingsRow(label: 'Licenses', onTap: () => showLicenses(context)),
        SettingsRow(label: 'Support', onTap: () {}),
        SettingsRow(label: "What's new", onTap: () {}),
        SettingsRow(label: 'GitHub repository', onTap: () {}),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return SettingsCard(
      children: [
        const SettingsRow(label: 'Version', value: '1.0.0', showChevron: false),
        SettingsRow(label: "What's new", onTap: () {}),
        SettingsRow(label: 'Licenses', onTap: () => showLicenses(context)),
        SettingsRow(label: 'Support', onTap: () {}),
        SettingsRow(label: 'GitHub repository', onTap: () {}),
      ],
    );
  }
}
