import 'package:flutter/material.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/utils/navigation_utils.dart';
import 'package:provider/provider.dart';

const adminUsersPath = '/admin/users';

const administrationNavItem = AppShellNavItem(
  path: '/admin',
  label: 'Administration',
  icon: Icons.admin_panel_settings_outlined,
  selectedIcon: Icons.admin_panel_settings,
  children: [
    AppShellNavItem(path: adminUsersPath, label: 'Users', icon: Icons.people_outline, selectedIcon: Icons.people),
  ],
);

bool canShowAdministration(BuildContext context) {
  final auth = context.watch<AuthProvider?>();
  final settings = context.watch<SyncSettingsProvider?>();
  return auth != null && settings != null && auth.canAdminister(settings);
}
