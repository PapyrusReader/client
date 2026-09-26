import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/profile_picker_sheet.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Reading preferences settings section for ProfilePage.
class ReadingSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const ReadingSettingsSection({super.key, this.isDesktop = false});

  static String capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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
        const SettingsSectionHeader(title: 'Reading'),
        SettingsRow(label: 'Default font', value: prefs.defaultFont, onTap: () => _showFontPicker(context)),
        SettingsRow(
          label: 'Line spacing',
          value: capitalize(prefs.lineSpacing),
          onTap: () => _showLineSpacingPicker(context),
        ),
        SettingsRow(
          label: 'Reading mode',
          value: capitalize(prefs.readingMode),
          onTap: () => _showReadingModePicker(context),
        ),
        SettingsToggleRow(
          label: 'Page turn animation',
          value: prefs.pageTurnAnimation,
          onChanged: (value) => prefs.pageTurnAnimation = value,
        ),
        SettingsRow(label: 'Reading profiles', onTap: () {}),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Typography',
          children: [
            _buildDropdownField(
              context,
              label: 'Default font',
              value: prefs.defaultFont,
              options: const [
                'Georgia',
                'Literata',
                'Bookerly',
                'Merriweather',
                'Noto Serif',
                'Atkinson Hyperlegible',
                'Open Dyslexic',
              ],
              onChanged: (value) => prefs.defaultFont = value,
            ),
            const SizedBox(height: Spacing.lg),
            Text('Default font size', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: prefs.defaultFontSize,
                    min: 10,
                    max: 32,
                    divisions: 22,
                    onChanged: (value) => prefs.defaultFontSize = value,
                  ),
                ),
                SizedBox(width: 48, child: Text('${prefs.defaultFontSize.toInt()}px', style: textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: Spacing.md),
            _buildSegmentedField<String>(
              context,
              label: 'Line spacing',
              value: prefs.lineSpacing,
              options: const {'compact': 'Compact', 'normal': 'Normal', 'relaxed': 'Relaxed'},
              onChanged: (value) => prefs.lineSpacing = value,
            ),
            const SizedBox(height: Spacing.md),
            _buildSegmentedField<String>(
              context,
              label: 'Text alignment',
              value: prefs.textAlignment,
              options: const {'left': 'Left', 'justify': 'Justify'},
              onChanged: (value) => prefs.textAlignment = value,
            ),
            const SizedBox(height: Spacing.md),
            _buildSegmentedField<String>(
              context,
              label: 'Margins',
              value: prefs.margins,
              options: const {'small': 'Small', 'medium': 'Medium', 'large': 'Large'},
              onChanged: (value) => prefs.margins = value,
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Behavior',
          children: [
            _buildSegmentedField<String>(
              context,
              label: 'Reading mode',
              value: prefs.readingMode,
              options: const {'paginated': 'Paginated', 'scroll': 'Continuous scroll'},
              onChanged: (value) => prefs.readingMode = value,
            ),
            const SizedBox(height: Spacing.md),
            SettingsToggleRow(
              label: 'Page turn animation',
              value: prefs.pageTurnAnimation,
              onChanged: (value) => prefs.pageTurnAnimation = value,
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(title: 'Annotations', children: [_buildHighlightColorField(context)]),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          children: [SettingsRow(label: 'Reading profiles', onTap: () {})],
        ),
      ],
    );
  }

  Widget _buildHighlightColorField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final prefs = context.watch<PreferencesProvider>();

    const highlightColors = {
      'yellow': Color(0xFFFFF176),
      'green': Color(0xFFA5D6A7),
      'blue': Color(0xFF90CAF9),
      'pink': Color(0xFFF48FB1),
      'orange': Color(0xFFFFCC80),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Default highlight color', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        Row(
          children: highlightColors.entries.map((entry) {
            final isSelected = prefs.defaultHighlightColor == entry.key;
            return Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: GestureDetector(
                onTap: () => prefs.defaultHighlightColor = entry.key,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: colorScheme.primary, width: 3)
                        : Border.all(color: colorScheme.outline, width: 1),
                  ),
                  child: isSelected ? Icon(Icons.check, size: 18, color: colorScheme.primary) : null,
                ),
              ),
            );
          }).toList(),
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

  void _showFontPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [
        ('Georgia', 'Georgia'),
        ('Literata', 'Literata'),
        ('Bookerly', 'Bookerly'),
        ('Merriweather', 'Merriweather'),
        ('Noto Serif', 'Noto Serif'),
        ('Atkinson Hyperlegible', 'Atkinson Hyperlegible'),
        ('Open Dyslexic', 'Open Dyslexic'),
      ],
      selected: prefs.defaultFont,
      onSelected: (value) => prefs.defaultFont = value,
    );
  }

  void _showLineSpacingPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Compact', 'compact'), ('Normal', 'normal'), ('Relaxed', 'relaxed')],
      selected: prefs.lineSpacing,
      onSelected: (value) => prefs.lineSpacing = value,
    );
  }

  void _showReadingModePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    showProfilePickerSheet(
      context,
      items: const [('Paginated', 'paginated'), ('Continuous scroll', 'scroll')],
      selected: prefs.readingMode,
      onSelected: (value) => prefs.readingMode = value,
    );
  }
}
