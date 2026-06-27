import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/storage_sync_controller.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
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
            _buildMobileAccountSection(context),
            _buildMobileAppearanceSection(context),
            _buildMobileReadingSection(context),
            _buildMobileLibrarySection(context),
            _buildMobileNotificationsSection(context),
            _buildMobileStorageSyncSection(context),
            _buildMobilePrivacyDataSection(context),
            _buildMobileAccessibilitySection(context),
            _buildMobileAboutSection(context),
            if (kDebugMode) _buildMobileDeveloperSection(context),
            const Divider(height: 1),
            _buildMenuItem(
              context,
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

  Widget _buildMobileAccountSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Account'),
        SettingsRow(label: 'Change password', onTap: () {}),
        SettingsRow(label: 'Linked accounts', onTap: () {}),
        SettingsRow(label: 'Two-factor authentication', onTap: () {}),
        SettingsRow(label: 'Active sessions', onTap: () {}),
        SettingsRow(label: 'Delete account', onTap: () {}),
      ],
    );
  }

  Widget _buildMobileAppearanceSection(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Appearance'),
        SettingsRow(label: 'Theme', value: _getThemeLabel(prefs.themeModePref), onTap: () => _showThemePicker(context)),
      ],
    );
  }

  Widget _buildMobileReadingSection(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Reading'),
        SettingsRow(label: 'Default font', value: prefs.defaultFont, onTap: () => _showFontPicker(context)),
        SettingsRow(
          label: 'Line spacing',
          value: _capitalize(prefs.lineSpacing),
          onTap: () => _showLineSpacingPicker(context),
        ),
        SettingsRow(
          label: 'Reading mode',
          value: _capitalize(prefs.readingMode),
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

  Widget _buildMobileLibrarySection(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Library'),
        SettingsRow(
          label: 'Default view',
          value: _capitalize(prefs.defaultViewMode),
          onTap: () => _showViewModePicker(context),
        ),
        SettingsRow(
          label: 'Default sort',
          value: _getSortOrderLabel(prefs.defaultSortOrder),
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

  Widget _buildMobileNotificationsSection(BuildContext context) {
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

  Widget _buildMobileStorageSyncSection(BuildContext context) {
    final controller = _storageSyncController(context);

    if (controller.isGuest) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(title: 'Storage & sync'),
          const SettingsRow(label: 'Library', value: 'Stored on this device'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
            child: Text(
              'Nothing is sent to Papyrus servers while offline mode is on.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          SettingsRow(
            label: 'Backup',
            value: 'Export or import a backup',
            onTap: () => _showOfflineBackupActions(context),
          ),
          SettingsRow(label: 'Clear local library', onTap: () => _confirmClearLocalLibrary(context)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Storage & sync'),
        SettingsRow(label: 'Current mode', value: controller.modeLabel),
        SettingsRow(label: 'Local database', value: controller.databaseLabel),
        SettingsRow(
          label: 'Metadata sync',
          value: controller.metadataSyncLabel,
          onTap: controller.shouldShowServerSettings ? () => _showSyncServerPicker(context) : null,
          showChevron: controller.shouldShowServerSettings,
        ),
        if (controller.shouldShowCustomServerUrls) ...[
          SettingsRow(label: 'API server', value: controller.syncSettings.activeApiConfig.serverBaseUri.toString()),
          SettingsRow(
            label: 'PowerSync service',
            value: controller.syncSettings.activeApiConfig.powerSyncServiceUri.toString(),
          ),
        ],
        if (controller.shouldShowServerSettings) ...[
          SettingsRow(label: 'Current status', value: controller.statusLabel),
          SettingsRow(label: 'Pending writes', value: controller.pendingWritesLabel),
          SettingsRow(label: 'Sync detail', value: controller.syncDetail),
        ],
        SettingsRow(
          label: 'Media storage',
          value: controller.mediaStorageLabel,
          onTap: controller.shouldShowServerSettings ? () => _showMediaStoragePicker(context) : null,
          showChevron: controller.shouldShowServerSettings,
        ),
        if (controller.mediaStorageRestrictionMessage case final message?)
          SettingsRow(label: 'Media policy', value: message),
        if (controller.canReconnect) SettingsRow(label: 'Reconnect sync', onTap: () => _handleReconnectSync(context)),
        if (controller.canClearGuestLibrary)
          SettingsRow(label: 'Clear local library', onTap: () => _confirmClearLocalLibrary(context)),
        if (controller.canClearAuthenticatedCache)
          SettingsRow(label: 'Clear account local cache', onTap: () => _confirmClearAuthenticatedCache(context)),
      ],
    );
  }

  Widget _buildMobilePrivacyDataSection(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Privacy & data'),
        SettingsToggleRow(
          label: 'Analytics',
          value: prefs.analyticsOptIn,
          onChanged: (value) => prefs.analyticsOptIn = value,
        ),
        SettingsRow(label: 'Privacy policy', onTap: () {}),
        SettingsRow(label: 'Export all data', onTap: () {}),
        SettingsRow(label: 'Import data', onTap: () {}),
        SettingsRow(label: 'Clear local data', onTap: () {}),
      ],
    );
  }

  Widget _buildMobileAccessibilitySection(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Accessibility'),
        SettingsToggleRow(
          label: 'Reduce animations',
          value: prefs.reduceAnimations,
          onChanged: (value) => prefs.reduceAnimations = value,
        ),
        SettingsToggleRow(
          label: 'Dyslexia-friendly font',
          value: prefs.dyslexiaFont,
          onChanged: (value) => prefs.dyslexiaFont = value,
        ),
      ],
    );
  }

  Widget _buildMobileAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'About'),
        SettingsRow(label: 'Version', value: '1.0.0', showChevron: false),
        SettingsRow(label: 'Licenses', onTap: () => _showLicenses(context)),
        SettingsRow(label: 'Support', onTap: () {}),
        SettingsRow(label: "What's new", onTap: () {}),
        SettingsRow(label: 'GitHub repository', onTap: () {}),
      ],
    );
  }

  Widget _buildMobileDeveloperSection(BuildContext context) {
    context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Developer options'),
        SettingsRow(label: 'Reload sample data', onTap: () {}),
        SettingsRow(label: 'Reset onboarding', onTap: () {}),
        SettingsRow(label: 'Performance overlay', onTap: () {}),
      ],
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
                    label: 'Storage & sync',
                    section: _ProfileSection.storageSync,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.shield_outlined,
                    label: 'Privacy & data',
                    section: _ProfileSection.privacyData,
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.accessibility_outlined,
                    label: 'Accessibility',
                    section: _ProfileSection.accessibility,
                  ),
                  _buildNavItem(context, icon: Icons.info_outline, label: 'About', section: _ProfileSection.about),
                  if (kDebugMode)
                    _buildNavItem(
                      context,
                      icon: Icons.code,
                      label: 'Developer options',
                      section: _ProfileSection.developerOptions,
                    ),
                  const SizedBox(height: Spacing.md),
                  Divider(height: 1, color: colorScheme.outlineVariant),
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
        return 'Storage & sync';
      case _ProfileSection.privacyData:
        return 'Privacy & data';
      case _ProfileSection.accessibility:
        return 'Accessibility';
      case _ProfileSection.about:
        return 'About';
      case _ProfileSection.developerOptions:
        return 'Developer options';
    }
  }

  Widget _buildSectionContent(BuildContext context) {
    switch (_selectedSection) {
      case _ProfileSection.account:
        return _buildAccountContent(context);
      case _ProfileSection.appearance:
        return _buildAppearanceContent(context);
      case _ProfileSection.reading:
        return _buildReadingContent(context);
      case _ProfileSection.library:
        return _buildLibraryContent(context);
      case _ProfileSection.notifications:
        return _buildNotificationsContent(context);
      case _ProfileSection.storageSync:
        return _buildStorageSyncContent(context);
      case _ProfileSection.privacyData:
        return _buildPrivacyDataContent(context);
      case _ProfileSection.accessibility:
        return _buildAccessibilityContent(context);
      case _ProfileSection.about:
        return _buildAboutContent(context);
      case _ProfileSection.developerOptions:
        return _buildDeveloperOptionsContent(context);
    }
  }

  // -- Account ----------------------------------------------------------------

  Widget _buildAccountContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          children: [
            Row(
              children: [
                _buildAvatar(context, size: 96),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getDisplayName(), style: textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(_getEmail(), style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: Spacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: () => _navigateToEditProfile(context),
                          child: const Text('Edit profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Security',
          children: [
            SettingsRow(label: 'Change password', onTap: () {}),
            SettingsRow(label: 'Two-factor authentication', onTap: () {}),
            SettingsRow(label: 'Active sessions', onTap: () {}),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Connected accounts',
          children: [
            SettingsRow(label: 'Google', value: _isGoogleLinked() ? 'Connected' : 'Not connected', onTap: () {}),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Danger zone',
          children: [SettingsRow(label: 'Delete account', onTap: () {})],
        ),
      ],
    );
  }

  // -- Appearance -------------------------------------------------------------

  Widget _buildAppearanceContent(BuildContext context) {
    return SettingsCard(children: [_buildThemeRadioGroup(context)]);
  }

  Widget _buildThemeRadioGroup(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        _buildRadioTile('Light', 'light'),
        _buildRadioTile('Dark', 'dark'),
        _buildRadioTile('E-ink', 'eink'),
        _buildRadioTile('System', 'system'),
      ],
    );
  }

  Widget _buildRadioTile(String label, String value) {
    final prefs = context.watch<PreferencesProvider>();
    final isSelected = prefs.themeModePref == value;

    return InkWell(
      onTap: () => prefs.themeModePref = value,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: Spacing.md),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  // -- Reading ----------------------------------------------------------------

  Widget _buildReadingContent(BuildContext context) {
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
              options: [
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

  // -- Library ----------------------------------------------------------------

  Widget _buildLibraryContent(BuildContext context) {
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

  // -- Notifications ----------------------------------------------------------

  Widget _buildNotificationsContent(BuildContext context) {
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

  // -- Storage & sync ---------------------------------------------------------

  Widget _buildStorageSyncContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = _storageSyncController(context);
    final connected = controller.syncState.connected;

    if (controller.isGuest) return _buildOfflineStorageSyncContent(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Library storage',
          children: [
            _buildInfoRow(context, label: 'Current mode', value: controller.modeLabel),
            _buildInfoRow(context, label: 'Local database', value: controller.databaseLabel),
            _buildInfoRow(context, label: 'Metadata sync', value: controller.metadataSyncLabel),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Metadata sync',
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Server', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: Spacing.xs),
                      Text(controller.metadataSyncLabel, style: textTheme.bodyLarge),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(
                    color: connected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    controller.statusLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: connected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (controller.shouldShowServerSettings) ...[
              _buildSegmentedField<SyncServerType>(
                context,
                label: 'Sync server',
                value: controller.syncSettings.serverType,
                options: const {SyncServerType.official: 'Official server', SyncServerType.custom: 'Custom server'},
                onChanged: (value) => _selectSyncServerType(context, value),
              ),
              if (controller.shouldShowCustomServerUrls) ...[
                const SizedBox(height: Spacing.md),
                _buildInfoRow(
                  context,
                  label: 'API server',
                  value: controller.syncSettings.activeApiConfig.serverBaseUri.toString(),
                ),
                _buildInfoRow(
                  context,
                  label: 'PowerSync service',
                  value: controller.syncSettings.activeApiConfig.powerSyncServiceUri.toString(),
                ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton(
                  onPressed: () => _showCustomServerDialog(context),
                  child: const Text('Edit custom server'),
                ),
              ],
              const SizedBox(height: Spacing.md),
              _buildInfoRow(context, label: 'Status', value: controller.statusLabel),
              _buildInfoRow(context, label: 'Pending writes', value: controller.pendingWritesLabel),
              const SizedBox(height: Spacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Text(
                  controller.syncDetail,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Text(
                  'Guest libraries stay fully offline. No server connection is used.',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            if (controller.canReconnect ||
                controller.canClearGuestLibrary ||
                controller.canClearAuthenticatedCache) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.start,
                children: [
                  if (controller.canReconnect)
                    OutlinedButton.icon(
                      onPressed: () => _handleReconnectSync(context),
                      icon: const Icon(Icons.sync, size: IconSizes.small),
                      label: const Text('Reconnect sync'),
                    ),
                  if (controller.canClearGuestLibrary)
                    OutlinedButton.icon(
                      onPressed: () => _confirmClearLocalLibrary(context),
                      icon: const Icon(Icons.delete_outline, size: IconSizes.small),
                      label: const Text('Clear local library'),
                    ),
                  if (controller.canClearAuthenticatedCache)
                    OutlinedButton.icon(
                      onPressed: () => _confirmClearAuthenticatedCache(context),
                      icon: const Icon(Icons.cleaning_services_outlined, size: IconSizes.small),
                      label: const Text('Clear account local cache'),
                    ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Media storage',
          children: [
            _buildInfoRow(context, label: 'Book files and covers', value: controller.mediaStorageLabel),
            if (controller.mediaStorageRestrictionMessage case final message?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Text(message, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ),
            if (controller.shouldShowServerSettings && controller.syncSettings.serverType == SyncServerType.custom) ...[
              const SizedBox(height: Spacing.md),
              _buildSegmentedField<MediaStorageBackend>(
                context,
                label: 'Media destination',
                value: controller.syncSettings.mediaStorageBackend,
                options: const {
                  MediaStorageBackend.local: 'Local device',
                  MediaStorageBackend.selfHosted: 'Self-hosted server',
                },
                onChanged: (value) => controller.syncSettings.mediaStorageBackend = value,
              ),
            ],
            if (controller.shouldShowServerSettings && controller.syncSettings.serverType == SyncServerType.official)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Text(
                  'Use a custom server if you want Papyrus-managed media storage. Third-party storage backends can be added later.',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOfflineStorageSyncContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return SettingsCard(
      title: 'Library storage',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your library is stored on this device.', style: textTheme.bodyLarge),
              const SizedBox(height: Spacing.sm),
              Text(
                'Nothing is sent to Papyrus servers while offline mode is on. Export a backup before changing devices or clearing app data.',
                style: mutedStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showBackupUnavailable(context, 'Backup export'),
              icon: const Icon(Icons.file_download_outlined, size: IconSizes.small),
              label: const Text('Export backup'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showBackupUnavailable(context, 'Backup import'),
              icon: const Icon(Icons.file_upload_outlined, size: IconSizes.small),
              label: const Text('Import backup'),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmClearLocalLibrary(context),
              icon: const Icon(Icons.delete_outline, size: IconSizes.small),
              label: const Text('Clear local library'),
            ),
          ],
        ),
      ],
    );
  }

  StorageSyncController _storageSyncController(BuildContext context) {
    return StorageSyncController(
      authProvider: context.watch<AuthProvider>(),
      powerSyncService: context.read<PapyrusPowerSyncService>(),
      syncSettings: context.watch<SyncSettingsProvider>(),
      syncState: context.watch<SyncState>(),
    );
  }

  Widget _buildInfoRow(BuildContext context, {required String label, required String value}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }

  // -- Privacy & data ---------------------------------------------------------

  Widget _buildPrivacyDataContent(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Analytics',
          children: [
            SettingsToggleRow(
              label: 'Send anonymous usage data',
              value: prefs.analyticsOptIn,
              onChanged: (value) => prefs.analyticsOptIn = value,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(
                'Help improve Papyrus by sharing anonymous usage statistics. '
                'No personal data or reading content is collected.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Data management',
          children: [
            SettingsRow(label: 'Export all data', onTap: () {}),
            SettingsRow(label: 'Import data', onTap: () {}),
            SettingsRow(label: 'Clear local data', onTap: () {}),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Legal',
          children: [SettingsRow(label: 'Privacy policy', onTap: () {})],
        ),
      ],
    );
  }

  // -- Accessibility ----------------------------------------------------------

  Widget _buildAccessibilityContent(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();

    return SettingsCard(
      children: [
        SettingsToggleRow(
          label: 'Reduce animations',
          value: prefs.reduceAnimations,
          onChanged: (value) => prefs.reduceAnimations = value,
        ),
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm, bottom: Spacing.md),
          child: Text(
            'Minimizes motion effects throughout the app. '
            'Separate from e-ink mode.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        SettingsToggleRow(
          label: 'Dyslexia-friendly font',
          value: prefs.dyslexiaFont,
          onChanged: (value) => prefs.dyslexiaFont = value,
        ),
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm, bottom: Spacing.md),
          child: Text(
            'Use OpenDyslexic font across the app interface.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // -- About ------------------------------------------------------------------

  Widget _buildAboutContent(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsRow(label: 'Version', value: '1.0.0', showChevron: false),
        SettingsRow(label: "What's new", onTap: () {}),
        SettingsRow(label: 'Licenses', onTap: () => _showLicenses(context)),
        SettingsRow(label: 'Support', onTap: () {}),
        SettingsRow(label: 'GitHub repository', onTap: () {}),
      ],
    );
  }

  // -- Developer options ------------------------------------------------------

  Widget _buildDeveloperOptionsContent(BuildContext context) {
    context.watch<PreferencesProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          title: 'Debug',
          children: [
            SettingsRow(label: 'Reload sample data', onTap: () {}),
            SettingsRow(label: 'Reset onboarding', onTap: () {}),
            SettingsRow(label: 'Performance overlay', onTap: () {}),
          ],
        ),
      ],
    );
  }

  // ============================================================================
  // USER DATA
  // ============================================================================

  String _getDisplayName() {
    final user = context.watch<AuthProvider>().user;
    return user?.displayName ?? 'Anonymous User';
  }

  String _getEmail() {
    final email = context.watch<AuthProvider>().user?.email;
    if (email == null || email.trim().isEmpty) return 'No email provided';
    return email;
  }

  String? _getAvatarUrl() {
    return context.watch<AuthProvider>().user?.avatarUrl;
  }

  String get _initials {
    final name = _getDisplayName();
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  bool _isGoogleLinked() {
    return false;
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  Future<void> _handleLogout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();
    if (context.mounted) context.go('/login');
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout(context);
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  void _navigateToEditProfile(BuildContext context) {
    context.go('/profile/edit');
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(context: context, applicationName: 'Papyrus', applicationVersion: '1.0.0');
  }

  void _showSyncServerPicker(BuildContext context) {
    final settings = context.read<SyncSettingsProvider>();

    _showPickerSheet(
      context,
      items: const [('Official server', 'official'), ('Custom server', 'custom')],
      selected: settings.serverType.name,
      onSelected: (value) {
        final serverType = value == SyncServerType.custom.name ? SyncServerType.custom : SyncServerType.official;
        unawaited(_selectSyncServerType(context, serverType));
      },
    );
  }

  Future<void> _selectSyncServerType(BuildContext context, SyncServerType value) async {
    final settings = context.read<SyncSettingsProvider>();

    if (value == SyncServerType.official) {
      settings.serverType = SyncServerType.official;
      return;
    }

    if (settings.customApiUrl.isEmpty || settings.customPowerSyncUrl.isEmpty) {
      await _showCustomServerDialog(context, switchToCustomAfterSave: true);
      return;
    }

    settings.serverType = SyncServerType.custom;
  }

  void _showMediaStoragePicker(BuildContext context) {
    final settings = context.read<SyncSettingsProvider>();
    final items = settings.serverType == SyncServerType.custom
        ? const [('Local device only', 'local'), ('Self-hosted server', 'selfHosted')]
        : const [('Local device only', 'local')];

    _showPickerSheet(
      context,
      items: items,
      selected: settings.mediaStorageBackend.name,
      onSelected: (value) {
        settings.mediaStorageBackend = value == MediaStorageBackend.selfHosted.name
            ? MediaStorageBackend.selfHosted
            : MediaStorageBackend.local;
      },
    );
  }

  Future<void> _showCustomServerDialog(BuildContext context, {bool switchToCustomAfterSave = false}) async {
    final settings = context.read<SyncSettingsProvider>();
    final apiController = TextEditingController(
      text: settings.customApiUrl.isEmpty ? 'http://localhost:8080' : settings.customApiUrl,
    );
    final powerSyncController = TextEditingController(
      text: settings.customPowerSyncUrl.isEmpty ? 'http://localhost:8081' : settings.customPowerSyncUrl,
    );
    final messenger = ScaffoldMessenger.of(context);

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Custom sync server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiController,
                decoration: const InputDecoration(labelText: 'Papyrus API URL'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: powerSyncController,
                decoration: const InputDecoration(labelText: 'PowerSync service URL'),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                try {
                  settings.setCustomServerUrls(apiUrl: apiController.text, powerSyncUrl: powerSyncController.text);
                  if (switchToCustomAfterSave) {
                    settings.serverType = SyncServerType.custom;
                  }
                  Navigator.pop(dialogContext);
                } catch (error) {
                  messenger.showSnackBar(SnackBar(content: Text('Invalid server URL: $error')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      apiController.dispose();
      powerSyncController.dispose();
    }
  }

  Future<void> _handleReconnectSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PapyrusPowerSyncService>().reconnect();
      messenger.showSnackBar(const SnackBar(content: Text('Sync reconnect requested.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not reconnect sync: $error')));
    }
  }

  void _showOfflineBackupActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export backup'),
              subtitle: const Text('Save a copy for another device'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showBackupUnavailable(context, 'Backup export');
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Import backup'),
              subtitle: const Text('Restore from a saved copy'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showBackupUnavailable(context, 'Backup import');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBackupUnavailable(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action is not available yet.')));
  }

  Future<void> _confirmClearLocalLibrary(BuildContext context) async {
    final confirmed = await _confirmStorageAction(
      context,
      title: 'Clear local library',
      message:
          'This deletes the library stored on this device. This cannot be undone unless you have exported a backup.',
      actionLabel: 'Clear library',
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PapyrusPowerSyncService>().clearGuestLibrary();
      messenger.showSnackBar(const SnackBar(content: Text('Local library cleared.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not clear local library: $error')));
    }
  }

  Future<void> _confirmClearAuthenticatedCache(BuildContext context) async {
    final confirmed = await _confirmStorageAction(
      context,
      title: 'Clear account local cache',
      message:
          'This clears only the local account cache on this device. Synced books remain on the server and will download again after reconnecting.',
      actionLabel: 'Clear local cache',
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PapyrusPowerSyncService>().clearAuthenticatedCache();
      messenger.showSnackBar(const SnackBar(content: Text('Account local cache cleared.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not clear account cache: $error')));
    }
  }

  Future<bool> _confirmStorageAction(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(actionLabel)),
            ],
          ),
        ) ??
        false;
  }

  // ============================================================================
  // REUSABLE FIELD BUILDERS
  // ============================================================================

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

  // ============================================================================
  // BOTTOM SHEET PICKERS (mobile)
  // ============================================================================

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _getThemeLabel(String theme) {
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

  String _getSortOrderLabel(String value) {
    const labels = {
      'title': 'Title',
      'author': 'Author',
      'date_added': 'Date added',
      'last_read': 'Last read',
      'rating': 'Rating',
    };
    return labels[value] ?? value;
  }

  void _showThemePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [('Light', 'light'), ('Dark', 'dark'), ('E-ink', 'eink'), ('System', 'system')],
      selected: prefs.themeModePref,
      onSelected: (value) => prefs.themeModePref = value,
    );
  }

  void _showFontPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [
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

    _showPickerSheet(
      context,
      items: [('Compact', 'compact'), ('Normal', 'normal'), ('Relaxed', 'relaxed')],
      selected: prefs.lineSpacing,
      onSelected: (value) => prefs.lineSpacing = value,
    );
  }

  void _showReadingModePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [('Paginated', 'paginated'), ('Continuous scroll', 'scroll')],
      selected: prefs.readingMode,
      onSelected: (value) => prefs.readingMode = value,
    );
  }

  void _showViewModePicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [('Grid', 'grid'), ('List', 'list'), ('Compact', 'compact')],
      selected: prefs.defaultViewMode,
      onSelected: (value) => prefs.defaultViewMode = value,
    );
  }

  void _showSortOrderPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [
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

    _showPickerSheet(
      context,
      items: [('Open Library', 'Open Library'), ('Google Books', 'Google Books')],
      selected: prefs.metadataSource,
      onSelected: (value) => prefs.metadataSource = value,
    );
  }

  void _showExportFormatPicker(BuildContext context) {
    final prefs = context.read<PreferencesProvider>();

    _showPickerSheet(
      context,
      items: [('Markdown', 'Markdown'), ('PDF', 'PDF'), ('TXT', 'TXT'), ('HTML', 'HTML')],
      selected: prefs.annotationExportFormat,
      onSelected: (value) => prefs.annotationExportFormat = value,
    );
  }

  void _showPickerSheet(
    BuildContext context, {
    required List<(String label, String value)> items,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.map((item) {
            return _buildPickerTile(
              context: sheetContext,
              title: item.$1,
              isSelected: selected == item.$2,
              onTap: () {
                onSelected(item.$2);
                Navigator.pop(sheetContext);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPickerTile({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(title),
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
      onTap: onTap,
    );
  }

  // ============================================================================
  // SHARED WIDGETS
  // ============================================================================

  Widget _buildMobileHeader(BuildContext context, {double avatarSize = 128}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        _buildAvatar(context, size: avatarSize),
        const SizedBox(height: Spacing.md),
        Text(_getDisplayName(), style: textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: Spacing.xs),
        Text(
          _getEmail(),
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          width: 200,
          child: OutlinedButton(onPressed: () => _navigateToEditProfile(context), child: const Text('Edit profile')),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, {required double size}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final avatarUrl = _getAvatarUrl();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(size / 2), color: colorScheme.primaryContainer),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  _initials,
                  style: textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: size * 0.35,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initials,
                style: textTheme.headlineMedium?.copyWith(color: colorScheme.onPrimaryContainer, fontSize: size * 0.35),
              ),
            ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool showChevron = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconColor = isDestructive ? colorScheme.error : colorScheme.onSurfaceVariant;
    final textColor = isDestructive ? colorScheme.error : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDestructive
                      ? colorScheme.errorContainer.withValues(alpha: 0.3)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: iconColor, size: IconSizes.medium),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(label, style: textTheme.bodyLarge?.copyWith(color: textColor)),
              ),
              if (showChevron) Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: IconSizes.medium),
            ],
          ),
        ),
      ),
    );
  }
}
