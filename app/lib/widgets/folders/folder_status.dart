import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/themes/design_tokens.dart';

String folderLastChecked(WatchedFolder folder, {bool includeLabel = true}) => folder.lastScan == null
    ? 'Not checked yet'
    : '${includeLabel ? 'Checked ' : ''}${DateFormat.yMMMd().add_Hm().format(folder.lastScan!.toLocal())}';

class FolderStatusLabel extends StatelessWidget {
  const FolderStatusLabel({
    super.key,
    required this.folder,
    this.shelfMissing = false,
    this.alignment = Alignment.centerLeft,
    this.reserveHeight = true,
  });

  final WatchedFolder folder;
  final bool shelfMissing;
  final AlignmentGeometry alignment;
  final bool reserveHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodyMedium!;
    final lineHeight = MediaQuery.textScalerOf(context).scale(style.fontSize!) * (style.height ?? 1.4);
    final progress = folder.progress;
    final needsAttention =
        shelfMissing ||
        const [FolderStatus.accessNeeded, FolderStatus.unavailable, FolderStatus.attention].contains(folder.status);
    final color = needsAttention ? colors.error : colors.onSurfaceVariant;
    final icon = switch (folder.status) {
      _ when shelfMissing => Icons.warning_amber_outlined,
      FolderStatus.scanning || FolderStatus.importing => Icons.sync,
      FolderStatus.upToDate => Icons.check,
      FolderStatus.paused when !folder.grant.persistent => Icons.upload_file_outlined,
      FolderStatus.paused => Icons.pause,
      FolderStatus.accessNeeded => Icons.lock_outline,
      FolderStatus.unavailable => Icons.folder_off_outlined,
      FolderStatus.attention => Icons.warning_amber_outlined,
    };
    final label = switch (folder.status) {
      FolderStatus.importing when progress != null =>
        '${progress.processed}/${progress.total}\n${progress.remaining} left',
      _ when shelfMissing => 'Shelf needs attention',
      FolderStatus.paused when !folder.grant.persistent => 'Manual import',
      _ => folder.statusLabel,
    };

    return SizedBox(
      height: reserveHeight ? lineHeight * 2 : null,
      child: Align(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: IconSizes.small, color: color),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                label,
                style: style.copyWith(color: color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: folder.status == FolderStatus.importing && progress != null
                    ? 'Importing books: ${progress.label}'
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
