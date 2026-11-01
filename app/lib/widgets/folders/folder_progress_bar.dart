import 'package:flutter/material.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class FolderProgressBar extends StatelessWidget {
  const FolderProgressBar({super.key, required this.folder});

  final WatchedFolder folder;

  @override
  Widget build(BuildContext context) {
    final importing = folder.status == FolderStatus.importing;
    final working = importing || folder.status == FolderStatus.scanning;

    return SizedBox(
      height: Spacing.xs,
      child: working
          ? AppLinearProgressIndicator(
              value: importing ? folder.progress?.fraction ?? 0 : null,
              minHeight: Spacing.xs,
              semanticsLabel:
                  '${folder.statusLabel} ${folder.name}${folder.progress == null ? '' : ': ${folder.progress!.label}'}',
            )
          : null,
    );
  }
}
