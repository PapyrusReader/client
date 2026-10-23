import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/services/app_info.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';

class AboutSettingsSection extends StatefulWidget {
  final bool isDesktop;

  const AboutSettingsSection({super.key, this.isDesktop = false});

  @override
  State<AboutSettingsSection> createState() => _AboutSettingsSectionState();
}

class _AboutSettingsSectionState extends State<AboutSettingsSection> {
  late final Future<PackageInfo> _packageInfo = loadAppInfo();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null ? (snapshot.hasError ? 'Unavailable' : 'Loading…') : AboutLinks.versionLabel(info);

        final externalLinkIndicator = Tooltip(
          message: 'Opens in a new browser tab',
          child: Icon(
            Icons.open_in_new,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: IconSizes.medium,
          ),
        );

        final rows = [
          SettingsRow(label: 'Version', value: version, showChevron: false),
          SettingsRow(label: 'Licenses', onTap: () => context.push('/profile/licenses')),
          SettingsRow(label: 'Support', onTap: () => context.push('/profile/support')),
          SettingsRow(
            label: "What's new",
            trailing: externalLinkIndicator,
            onTap: () => AboutLinks.open(context, info == null ? AboutLinks.releases : AboutLinks.release(info)),
          ),
          SettingsRow(
            label: 'GitHub repository',
            trailing: externalLinkIndicator,
            onTap: () => AboutLinks.open(context, AboutLinks.repository),
          ),
        ];

        if (widget.isDesktop) {
          return SettingsCard(children: rows);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionHeader(title: 'About'),
            ...rows,
          ],
        );
      },
    );
  }
}
