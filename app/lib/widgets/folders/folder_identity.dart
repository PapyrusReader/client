import 'package:flutter/material.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/themes/design_tokens.dart';

class FolderIdentity extends StatelessWidget {
  const FolderIdentity({super.key, required this.folder, this.titleStyle});

  final WatchedFolder folder;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: TouchTargets.desktopRecommended,
          height: TouchTargets.desktopRecommended,
          decoration: ShapeDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            shape: theme.cardTheme.shape ?? const RoundedRectangleBorder(),
          ),
          child: Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(folder.name, style: titleStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (folder.grant.location != folder.grant.name) ...[
                const SizedBox(height: Spacing.xs),
                Tooltip(
                  message: folder.grant.location,
                  child: Text(
                    folder.grant.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
