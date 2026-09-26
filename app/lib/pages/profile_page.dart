import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/profile/about_settings_section.dart';
import 'package:papyrus/widgets/profile/accessibility_settings_section.dart';
import 'package:papyrus/widgets/profile/account_settings_section.dart';
import 'package:papyrus/widgets/profile/appearance_settings_section.dart';
import 'package:papyrus/widgets/profile/developer_settings_section.dart';
import 'package:papyrus/widgets/profile/library_settings_section.dart';
import 'package:papyrus/widgets/profile/notifications_settings_section.dart';
import 'package:papyrus/widgets/profile/privacy_settings_section.dart';
import 'package:papyrus/widgets/profile/profile_header.dart';
import 'package:papyrus/widgets/profile/profile_menu_item.dart';
import 'package:papyrus/widgets/profile/reading_settings_section.dart';
import 'package:papyrus/widgets/profile/storage_sync_settings_section.dart';
import 'package:provider/provider.dart';

enum _ProfileSection {
  account,
  appearance,
  reading,
  library,
  notifications,
  storageSync,
  privacyData,
  accessibility,
  about,
  developerOptions,
}

/// User profile page with account settings, preferences, and app configuration.
///
/// Mobile: AppBar with title, inline settings sections.
/// Desktop: Sidebar nav + content panel (similar to GitHub Settings).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  _ProfileSection _selectedSection = _ProfileSection.account;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= Breakpoints.desktopSmall;

    if (isDesktop) return _buildDesktopLayout(context);
    return _buildMobileLayout(context);
  }

  // ============================================================================
  // MOBILE LAYOUT
  // ============================================================================

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _buildMobileHeader(context),
            const SizedBox(height: Spacing.md),
            const AccountSettingsSection(isDesktop: false),
            const AppearanceSettingsSection(isDesktop: false),
            const ReadingSettingsSection(isDesktop: false),
            const LibrarySettingsSection(isDesktop: false),
            const NotificationsSettingsSection(isDesktop: false),
            const StorageSyncSettingsSection(isDesktop: false),
            StorageSyncSettingsSection.buildMobileAcquisitionSection(context),
            const PrivacySettingsSection(isDesktop: false),
            const AccessibilitySettingsSection(isDesktop: false),
            if (kDebugMode) const DeveloperSettingsSection(isDesktop: false),
            const AboutSettingsSection(isDesktop: false),
            const Divider(height: 1),
            ProfileMenuItem(
              icon: Icons.logout,
              label: 'Log out',
              isDestructive: true,
              showChevron: false,
              onTap: () => _showLogoutConfirmation(context),
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeader(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final displayName = user?.displayName ?? 'Anonymous User';
    final userEmail = user?.email;
    final email = (userEmail != null && userEmail.trim().isNotEmpty) ? userEmail : 'No email provided';

    return ProfileHeader(
      displayName: displayName,
      email: email,
      avatarUrl: user?.avatarUrl,
      onEditProfile: () => context.go('/profile/edit'),
      isDesktopLayout: false,
    );
  }

  // ============================================================================
  // DESKTOP LAYOUT
  // ============================================================================

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _buildDesktopNav(context),
            const VerticalDivider(width: 1),
            Expanded(child: _buildDesktopContent(context)),
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
                    section: _ProfileSection.account,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.palette_outlined,
                    label: 'Appearance',
                    section: _ProfileSection.appearance,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.auto_stories_outlined,
                    label: 'Reading',
                    section: _ProfileSection.reading,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.library_books_outlined,
                    label: 'Library',
                    section: _ProfileSection.library,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    section: _ProfileSection.notifications,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.cloud_outlined,
                    label: 'Storage',
                    section: _ProfileSection.storageSync,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.shield_outlined,
                    label: 'Privacy',
                    section: _ProfileSection.privacyData,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.accessibility_outlined,
                    label: 'Accessibility',
                    section: _ProfileSection.accessibility,
                  ),
                  if (kDebugMode)
                    _buildNavItem(
                      context,
                      icon: Icons.code,
                      label: 'Developer options',
                      section: _ProfileSection.developerOptions,
                    ),
                  _buildNavItem(context, icon: Icons.info_outline, label: 'About', section: _ProfileSection.about),
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
    _ProfileSection? section,
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = section != null && _selectedSection == section;

    final iconColor = isDestructive
        ? colorScheme.error
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final textColor = isDestructive
        ? colorScheme.error
        : isSelected
        ? colorScheme.onPrimaryContainer
        : null;
    final bgColor = isSelected ? colorScheme.primaryContainer : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap:
              onTap ??
              () {
                if (section != null) {
                  setState(() => _selectedSection = section);
                }
              },
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: IconSizes.medium),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // DESKTOP CONTENT PANEL
  // ============================================================================

  Widget _buildDesktopContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.xl),
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

  String get _sectionTitle {
    switch (_selectedSection) {
      case _ProfileSection.account:
        return 'Account';
      case _ProfileSection.appearance:
        return 'Appearance';
      case _ProfileSection.reading:
        return 'Reading';
      case _ProfileSection.library:
        return 'Library';
      case _ProfileSection.notifications:
        return 'Notifications';
      case _ProfileSection.storageSync:
        return 'Storage';
      case _ProfileSection.privacyData:
        return 'Privacy & data';
      case _ProfileSection.accessibility:
        return 'Accessibility';
      case _ProfileSection.developerOptions:
        return 'Developer options';
      case _ProfileSection.about:
        return 'About';
    }
  }

  Widget _buildSectionContent(BuildContext context) {
    switch (_selectedSection) {
      case _ProfileSection.account:
        return const AccountSettingsSection(isDesktop: true);
      case _ProfileSection.appearance:
        return const AppearanceSettingsSection(isDesktop: true);
      case _ProfileSection.reading:
        return const ReadingSettingsSection(isDesktop: true);
      case _ProfileSection.library:
        return const LibrarySettingsSection(isDesktop: true);
      case _ProfileSection.notifications:
        return const NotificationsSettingsSection(isDesktop: true);
      case _ProfileSection.storageSync:
        return const StorageSyncSettingsSection(isDesktop: true);
      case _ProfileSection.privacyData:
        return const PrivacySettingsSection(isDesktop: true);
      case _ProfileSection.accessibility:
        return const AccessibilitySettingsSection(isDesktop: true);
      case _ProfileSection.about:
        return const AboutSettingsSection(isDesktop: true);
      case _ProfileSection.developerOptions:
        return const DeveloperSettingsSection(isDesktop: true);
    }
  }

  // ============================================================================
  // LOGOUT
  // ============================================================================

  Future<void> _handleLogout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();
    if (context.mounted) context.go('/login');
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
