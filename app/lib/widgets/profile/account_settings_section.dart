import 'package:flutter/material.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/widgets/profile/account_profile_form.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/profile/account_deletion_dialog.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Account settings section for ProfilePage.
class AccountSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const AccountSettingsSection({super.key, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }

    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Account',
          padding: EdgeInsets.only(bottom: Spacing.md),
        ),
        _buildProfileForm(context),
        const SizedBox(height: Spacing.lg),
        const SettingsRow(label: 'Change password', enabled: false, showChevron: false),
        _buildGoogleConnection(context),
        const SettingsRow(label: 'Two-factor authentication', enabled: false, showChevron: false),
        const SettingsRow(label: 'Active sessions', enabled: false, showChevron: false),
        SettingsRow(
          label: 'Delete account',
          enabled: context.watch<AuthProvider>().isSignedIn || context.watch<AuthProvider>().isOfflineMode,
          onTap: () => showAccountDeletionDialog(context),
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(children: [_buildProfileForm(context)]),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Security',
          children: [
            const SettingsRow(label: 'Change password', enabled: false, showChevron: false),
            const SettingsRow(label: 'Two-factor authentication', enabled: false, showChevron: false),
            const SettingsRow(label: 'Active sessions', enabled: false, showChevron: false),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Connected accounts',
          children: [_buildGoogleConnection(context)],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Danger zone',
          children: [
            SettingsRow(
              label: 'Delete account',
              enabled: auth.isSignedIn || auth.isOfflineMode,
              onTap: () => showAccountDeletionDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoogleConnection(BuildContext context) {
    final providers = context.watch<AuthProvider>().user?.connectedProviders ?? const <String>[];

    return SettingsRow(
      label: 'Google',
      value: providers.contains('google') ? 'Connected' : 'Not connected',
      showChevron: false,
    );
  }

  Widget _buildProfileForm(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AccountProfileForm(key: ValueKey(auth.user?.userId ?? 'guest'));
  }
}
