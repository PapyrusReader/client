import 'package:flutter/material.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/services/support_api_client.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';

class SupportConfirmation extends StatelessWidget {
  const SupportConfirmation({super.key, required this.issue});

  final SupportIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text('Thank you for helping us improve.', style: textTheme.titleLarge),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'Your report has been added to our queue. You can follow updates and join the conversation on GitHub.',
          style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stackAction = constraints.maxWidth < 400 || MediaQuery.textScalerOf(context).scale(16) > 24;
                final reference = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GitHub issue', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: Spacing.xs),
                    Text('#${issue.number}', style: textTheme.titleMedium),
                  ],
                );
                final action = Tooltip(
                  message: 'Opens in a new browser tab',
                  child: TextButton.icon(
                    onPressed: () => AboutLinks.open(context, issue.url),
                    icon: const Icon(Icons.open_in_new, size: IconSizes.small),
                    iconAlignment: IconAlignment.end,
                    label: const Text('View issue'),
                  ),
                );

                if (stackAction) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      reference,
                      const SizedBox(height: Spacing.sm),
                      action,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: reference),
                    const SizedBox(width: Spacing.md),
                    action,
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
