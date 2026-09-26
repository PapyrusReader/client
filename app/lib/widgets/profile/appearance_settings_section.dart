import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/profile_picker_sheet.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Appearance and theme settings section for ProfilePage.
class AppearanceSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const AppearanceSettingsSection({super.key, this.isDesktop = false});

  static String getThemeLabel(String theme) {
    switch (theme) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      case 'eink':
        return 'E-ink';
      case 'system':
      default:
        return 'System';
    }
  }

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
        const SettingsSectionHeader(title: 'Appearance'),
        SettingsRow(label: 'Theme', value: getThemeLabel(prefs.themeModePref), onTap: () => _showThemePicker(context)),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(title: 'Theme', children: [_buildThemeRadioGroup(context)]),
      ],
    );
  }

  Widget _buildThemeRadioGroup(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildRadioTile(context, 'Light', 'light'),
          _buildRadioTile(context, 'Dark', 'dark'),
          _buildRadioTile(context, 'E-ink', 'eink'),
          _buildRadioTile(context, 'System default', 'system'),
        ],
      ),
    );
  }

  Widget _buildRadioTile(BuildContext context, String label, String value) {
    final prefs = context.watch<PreferencesProvider>();
    final isSelected = prefs.themeModePref == value;

    return ListTile(
      title: Text(label),
      leading: Radio<String>(
        value: value,
        // ignore: deprecated_member_use
        groupValue: prefs.themeModePref,
        // ignore: deprecated_member_use
        onChanged: (newValue) {
          if (newValue != null) prefs.themeModePref = newValue;
        },
      ),
      onTap: () => prefs.themeModePref = value,
      selected: isSelected,
    );
  }

  void _showThemePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Light', 'light'), ('Dark', 'dark'), ('E-ink', 'eink'), ('System', 'system')],
      selected: prefs.themeModePref,
      onSelected: (value) => prefs.themeModePref = value,
    );
  }
}
