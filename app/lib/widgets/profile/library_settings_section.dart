import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/profile_picker_sheet.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Library settings section for ProfilePage.
class LibrarySettingsSection extends StatelessWidget {
  final bool isDesktop;

  const LibrarySettingsSection({super.key, this.isDesktop = false});

  static String capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String getSortOrderLabel(String value) {
    const labels = {
      'title': 'Title',
      'author': 'Author',
      'date_added': 'Date added',
      'last_read': 'Last read',
      'rating': 'Rating',
    };
    return labels[value] ?? value;
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
        const SettingsSectionHeader(title: 'Library'),
        SettingsRow(
          label: 'Default view',
          value: capitalize(prefs.defaultViewMode),
          onTap: () => _showViewModePicker(context),
        ),
        SettingsRow(
          label: 'Default sort',
          value: getSortOrderLabel(prefs.defaultSortOrder),
          onTap: () => _showSortOrderPicker(context),
        ),
        SettingsRow(
          label: 'Metadata source',
          value: prefs.metadataSource,
          onTap: () => _showMetadataSourcePicker(context),
        ),
        SettingsRow(
          label: 'Export format',
          value: prefs.annotationExportFormat,
          onTap: () => _showExportFormatPicker(context),
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Display',
          children: [
            _buildSegmentedField<String>(
              context,
              label: 'Default view mode',
              value: prefs.defaultViewMode,
              options: const {'grid': 'Grid', 'list': 'List', 'compact': 'Compact'},
              onChanged: (value) => prefs.defaultViewMode = value,
            ),
            const SizedBox(height: Spacing.md),
            _buildDropdownField(
              context,
              label: 'Default sort order',
              value: prefs.defaultSortOrder,
              options: const ['title', 'author', 'date_added', 'last_read', 'rating'],
              labels: const {
                'title': 'Title',
                'author': 'Author',
                'date_added': 'Date added',
                'last_read': 'Last read',
                'rating': 'Rating',
              },
              onChanged: (value) => prefs.defaultSortOrder = value,
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Data',
          children: [
            _buildSegmentedField<String>(
              context,
              label: 'Metadata source',
              value: prefs.metadataSource,
              options: const {'Open Library': 'Open Library', 'Google Books': 'Google Books'},
              onChanged: (value) => prefs.metadataSource = value,
            ),
            const SizedBox(height: Spacing.md),
            _buildDropdownField(
              context,
              label: 'Annotation export format',
              value: prefs.annotationExportFormat,
              options: const ['Markdown', 'PDF', 'TXT', 'HTML'],
              onChanged: (value) => prefs.annotationExportFormat = value,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> options,
    Map<String, String>? labels,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        DropdownMenu<String>(
          initialSelection: value,
          expandedInsets: EdgeInsets.zero,
          dropdownMenuEntries: options.map((option) {
            final displayLabel = labels?[option] ?? option;
            return DropdownMenuEntry(value: option, label: displayLabel);
          }).toList(),
          onSelected: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ],
    );
  }

  Widget _buildSegmentedField<T>(
    BuildContext context, {
    required String label,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            segments: options.entries.map((entry) {
              return ButtonSegment<T>(value: entry.key, label: Text(entry.value));
            }).toList(),
            selected: {value},
            onSelectionChanged: (selected) {
              onChanged(selected.first);
            },
            showSelectedIcon: false,
          ),
        ),
      ],
    );
  }

  void _showViewModePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Grid', 'grid'), ('List', 'list'), ('Compact', 'compact')],
      selected: prefs.defaultViewMode,
      onSelected: (value) => prefs.defaultViewMode = value,
    );
  }

  void _showSortOrderPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [
        ('Title', 'title'),
        ('Author', 'author'),
        ('Date added', 'date_added'),
        ('Last read', 'last_read'),
        ('Rating', 'rating'),
      ],
      selected: prefs.defaultSortOrder,
      onSelected: (value) => prefs.defaultSortOrder = value,
    );
  }

  void _showMetadataSourcePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Open Library', 'Open Library'), ('Google Books', 'Google Books')],
      selected: prefs.metadataSource,
      onSelected: (value) => prefs.metadataSource = value,
    );
  }

  void _showExportFormatPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Markdown', 'Markdown'), ('PDF', 'PDF'), ('TXT', 'TXT'), ('HTML', 'HTML')],
      selected: prefs.annotationExportFormat,
      onSelected: (value) => prefs.annotationExportFormat = value,
    );
  }
}
