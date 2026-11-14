import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/profile/profile_picker_sheet.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

class MetadataSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const MetadataSettingsSection({super.key, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();

    final source = SettingsRow(
      label: 'Search source',
      value: preferences.metadataSource,
      onTap: () => showProfilePickerSheet(
        context,
        title: 'Metadata source',
        items: const [('Open Library', 'Open Library'), ('Google Books', 'Google Books')],
        selected: preferences.metadataSource,
        onSelected: (value) => preferences.metadataSource = value,
      ),
    );

    return isDesktop ? SettingsCard(title: 'Metadata', children: [source]) : source;
  }
}
