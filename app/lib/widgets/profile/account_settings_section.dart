import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
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
        const SettingsSectionHeader(title: 'Account'),
        SettingsRow(label: 'Change password', onTap: () {}),
        SettingsRow(label: 'Linked accounts', onTap: () {}),
        SettingsRow(label: 'Two-factor authentication', onTap: () {}),
        SettingsRow(label: 'Active sessions', onTap: () {}),
        SettingsRow(label: 'Delete account', onTap: () {}),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final displayName = user?.displayName ?? 'Anonymous User';
    final userEmail = user?.email;
    final email = (userEmail != null && userEmail.trim().isNotEmpty) ? userEmail : 'No email provided';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          children: [
            Row(
              children: [
                _buildAvatar(context, displayName: displayName, avatarUrl: user?.avatarUrl, size: 96),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(email, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: Spacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: () => context.go('/profile/edit'),
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
          children: [SettingsRow(label: 'Google', value: 'Not connected', onTap: () {})],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          title: 'Danger zone',
          children: [SettingsRow(label: 'Delete account', onTap: () {})],
        ),
      ],
    );
  }

  Widget _buildAvatar(
    BuildContext context, {
    required String displayName,
    required String? avatarUrl,
    required double size,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final initials = _getInitials(displayName);

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
                  initials,
                  style: textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: size * 0.35,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials,
                style: textTheme.headlineMedium?.copyWith(color: colorScheme.onPrimaryContainer, fontSize: size * 0.35),
              ),
            ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
