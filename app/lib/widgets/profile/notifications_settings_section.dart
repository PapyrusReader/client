import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Notifications settings section for ProfilePage.
class NotificationsSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const NotificationsSettingsSection({super.key, this.isDesktop = false});

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
        const SettingsSectionHeader(title: 'Notifications'),
        SettingsToggleRow(
          label: 'Goal reminders',
          value: prefs.goalReminders,
          onChanged: (value) => prefs.goalReminders = value,
        ),
        SettingsToggleRow(
          label: 'Streak alerts',
          value: prefs.streakAlerts,
          onChanged: (value) => prefs.streakAlerts = value,
        ),
        SettingsToggleRow(
          label: 'Sync status',
          value: prefs.syncStatusNotifications,
          onChanged: (value) => prefs.syncStatusNotifications = value,
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return SettingsCard(
      children: [
        SettingsToggleRow(
          label: 'Goal reminders',
          value: prefs.goalReminders,
          onChanged: (value) => prefs.goalReminders = value,
        ),
        SettingsToggleRow(
          label: 'Streak alerts',
          value: prefs.streakAlerts,
          onChanged: (value) => prefs.streakAlerts = value,
        ),
        SettingsToggleRow(
          label: 'Sync status',
          value: prefs.syncStatusNotifications,
          onChanged: (value) => prefs.syncStatusNotifications = value,
        ),
      ],
    );
  }
}
