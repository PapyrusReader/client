import 'dart:async';

import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';
import 'package:papyrus/widgets/profile/accessibility_settings_section.dart';
import 'package:papyrus/widgets/profile/account_settings_section.dart';
import 'package:papyrus/widgets/profile/appearance_settings_section.dart';
import 'package:papyrus/widgets/profile/storage_sync_settings_section.dart';
import 'package:provider/provider.dart';

enum ProfileSection {
  account('account', 'Account', Icons.person_outline),
  appearance('appearance', 'Appearance', Icons.palette_outlined),
  storageSync('storage', 'Storage', Icons.cloud_outlined),
  accessibility('accessibility', 'Accessibility', Icons.accessibility_outlined),
  about('about', 'About', Icons.info_outline);

  const ProfileSection(this.path, this.title, this.icon);

  final String path;
  final String title;
  final IconData icon;
}

/// Compact settings index with pushed detail pages, or a wide sidebar and panel.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.section});

  final ProfileSection? section;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ProfileSection _selectedSection = widget.section ?? ProfileSection.account;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= Breakpoints.desktopSmall;

    if (isDesktop) {
      return _buildDesktopLayout(context);
    }

    if (widget.section != null) {
      return _buildMobileDetail(context);
    }

    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final preferences = context.watch<PreferencesProvider>();

    return Scaffold(
      appBar: AppPageBar(context: context, title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey('settings-index'),
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          children: [
            _buildMobileItem(
              context,
              ProfileSection.account,
              subtitle: auth.isOfflineMode ? 'Offline profile' : auth.profileDisplayName,
            ),
            const Divider(height: Spacing.lg),
            _buildMobileItem(
              context,
              ProfileSection.appearance,
              subtitle: '${AppearanceSettingsSection.getThemeLabel(preferences.themeModePref)} theme, page layout',
            ),
            _buildMobileItem(context, ProfileSection.accessibility, subtitle: 'Text size, contrast, motion'),
            const Divider(height: Spacing.lg),
            _buildMobileItem(
              context,
              ProfileSection.storageSync,
              subtitle: auth.isOfflineMode ? 'On-device library, backups' : 'Sync, servers, downloads',
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.notifications_outlined),
              title: Text('Notifications'),
              subtitle: Text('Not available yet'),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.shield_outlined),
              title: Text('Privacy'),
              subtitle: Text('Not available yet'),
            ),
            const Divider(height: Spacing.lg),
            _buildMobileItem(context, ProfileSection.about, subtitle: 'Version, support, licenses'),
            const Divider(height: Spacing.lg),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Log out', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => _showLogoutConfirmation(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileItem(BuildContext context, ProfileSection section, {required String subtitle}) {
    return ListTile(
      leading: Icon(section.icon),
      title: Text(section.title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/profile/${section.path}'),
    );
  }

  Widget _buildMobileDetail(BuildContext context) {
    return Scaffold(
      appBar: AppPageBar(context: context, title: Text(_selectedSection.title), leading: const BackButton()),
      body: SafeArea(
        child: ListView(
          key: PageStorageKey('settings-${_selectedSection.path}'),
          padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.lg),
          children: [
            _buildSectionContent(context, isDesktop: false),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusTraversalGroup(child: _buildDesktopNav(context)),
            const VerticalDivider(width: 1),
            Expanded(child: FocusTraversalGroup(child: _buildDesktopContent(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopNav(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 240,
      child: Column(
        children: [
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Column(
                children: [
                  _buildNavItem(
                    context,
                    icon: Icons.person_outline,
                    label: 'Account',
                    section: ProfileSection.account,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.palette_outlined,
                    label: 'Appearance',
                    section: ProfileSection.appearance,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    enabled: false,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.cloud_outlined,
                    label: 'Storage',
                    section: ProfileSection.storageSync,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.shield_outlined,
                    label: 'Privacy',
                    enabled: false,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.accessibility_outlined,
                    label: 'Accessibility',
                    section: ProfileSection.accessibility,
                  ),
                  _buildNavItem(context, icon: Icons.info_outline, label: 'About', section: ProfileSection.about),
                  const SizedBox(height: Spacing.sm),
                  Divider(height: 1, color: colorScheme.outlineVariant),
                  const SizedBox(height: Spacing.sm),
                  _buildNavItem(
                    context,
                    icon: Icons.logout,
                    label: 'Log out',
                    isDestructive: true,
                    onTap: () => _showLogoutConfirmation(context),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    ProfileSection? section,
    bool enabled = true,
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = section != null && _selectedSection == section;

    final iconColor = switch (isDestructive) {
      true => colorScheme.error,
      false when isSelected => colorScheme.onPrimaryContainer,
      false => colorScheme.onSurfaceVariant,
    };

    final textColor = switch (isDestructive) {
      true => colorScheme.error,
      false when isSelected => colorScheme.onPrimaryContainer,
      false => null,
    };

    final bgColor = isSelected ? colorScheme.primaryContainer : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        enabled: enabled,
        button: true,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            canRequestFocus: enabled,
            onTap: enabled ? onTap ?? () => setState(() => _selectedSection = section!) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
              child: Row(
                children: [
                  Icon(icon, color: enabled ? iconColor : Theme.of(context).disabledColor, size: IconSizes.medium),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodyMedium?.copyWith(
                        color: enabled ? textColor : Theme.of(context).disabledColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.lg),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_sectionTitle, style: textTheme.headlineMedium),
              const SizedBox(height: Spacing.lg),
              _buildSectionContent(context),
            ],
          ),
        ),
      ),
    );
  }

  String get _sectionTitle => _selectedSection.title;

  Widget _buildSectionContent(BuildContext context, {bool isDesktop = true}) {
    return switch (_selectedSection) {
      ProfileSection.account => AccountSettingsSection(isDesktop: isDesktop, showHeader: false),
      ProfileSection.appearance => AppearanceSettingsSection(isDesktop: isDesktop, showHeader: false),
      ProfileSection.storageSync => StorageSyncSettingsSection(isDesktop: isDesktop, showHeader: false),
      ProfileSection.accessibility => AccessibilitySettingsSection(isDesktop: isDesktop, showHeader: false),
      ProfileSection.about => AboutSettingsSection(isDesktop: isDesktop, showHeader: false),
    };
  }

  Future<void> _handleLogout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();

    if (context.mounted) {
      context.go('/login');
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      animationStyle: AppMotion.animationStyle(context),
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleLogout(context);
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
