import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/profile_picker_sheet.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

class AccessibilitySettingsSection extends StatelessWidget {
  final bool isDesktop;

  const AccessibilitySettingsSection({super.key, this.isDesktop = false});

  static String enlargementLabel(double value) => value == 1 ? 'System default' : '+${((value - 1) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[
      SettingsRow(
        label: 'Interface text enlargement',
        value: enlargementLabel(prefs.interfaceTextEnlargement),
        onTap: () => showProfilePickerSheet(
          context,
          title: 'Interface text enlargement',
          items: PreferencesProvider.interfaceTextEnlargements
              .map((value) => (enlargementLabel(value), '$value'))
              .toList(),
          selected: '${prefs.interfaceTextEnlargement}',
          onSelected: (value) => prefs.interfaceTextEnlargement = double.parse(value),
        ),
      ),
      SettingsRow(
        label: 'Interface font',
        value: prefs.dyslexiaFont ? 'OpenDyslexic' : 'System default',
        onTap: () => showProfilePickerSheet(
          context,
          title: 'Interface font',
          items: const [('System default', 'system'), ('OpenDyslexic', 'opendyslexic')],
          selected: prefs.dyslexiaFont ? 'opendyslexic' : 'system',
          onSelected: (value) => prefs.dyslexiaFont = value == 'opendyslexic',
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Semantics(
          label: 'Interface text preview',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              'The quick brown fox jumps over the lazy dog.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ),
      ),
      SettingsToggleRow(
        label: 'Increase contrast',
        value: prefs.isEinkMode || prefs.increaseContrast,
        onChanged: prefs.isEinkMode ? null : (value) => prefs.increaseContrast = value,
      ),
      _description(
        context,
        prefs.isEinkMode
            ? 'E-ink already provides increased contrast.'
            : 'Always increase contrast. When off, follows your device setting.',
      ),
      SettingsToggleRow(
        label: 'Bold interface text',
        value: prefs.boldInterfaceText,
        onChanged: (value) => prefs.boldInterfaceText = value,
      ),
      _description(context, 'Always use bold interface text. When off, follows your device setting.'),
      SettingsToggleRow(
        label: 'Reduce animations',
        value: prefs.reduceAnimations,
        onChanged: (value) => prefs.reduceAnimations = value,
      ),
      _description(context, 'Your device’s reduced-motion setting is always respected. E-ink also reduces motion.'),
    ];

    if (isDesktop) {
      return SettingsCard(children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Accessibility'),
        ...children,
      ],
    );
  }

  Widget _description(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm, bottom: Spacing.md),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
