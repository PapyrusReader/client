import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/folders/folder_identity.dart';
import 'package:papyrus/widgets/folders/folder_status.dart';
import 'package:papyrus/widgets/folders/folder_progress_bar.dart';
import 'package:provider/provider.dart';

class FolderTable extends StatelessWidget {
  const FolderTable({
    super.key,
    required this.folders,
    required this.busy,
    required this.padding,
    required this.onAction,
  });

  final List<WatchedFolder> folders;
  final bool busy;
  final EdgeInsets padding;
  final void Function(WatchedFolder folder, String action) onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth - padding.horizontal >= 920 && MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      final theme = Theme.of(context);

      return ListView.builder(
        padding: padding,
        itemCount: folders.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                const Divider(height: 1),
                if (wide)
                  Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: DefaultTextStyle(
                      style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      child: const _FolderColumns(
                        identity: Text('FOLDER'),
                        status: Text('STATUS'),
                        books: Text('BOOKS'),
                        shelf: Text('DESTINATION SHELF'),
                        checked: Text('LAST CHECKED'),
                        action: SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            );
          }

          if (index == folders.length + 1) {
            return const Divider(height: 1);
          }

          final folder = folders[index - 1];

          return _FolderRow(
            key: ValueKey(folder.id),
            folder: folder,
            busy: busy,
            wide: wide,
            showDivider: wide || index > 1,
            onAction: (action) => onAction(folder, action),
          );
        },
      );
    },
  );
}

class _FolderColumns extends StatelessWidget {
  const _FolderColumns({
    required this.identity,
    required this.status,
    required this.books,
    required this.shelf,
    required this.checked,
    required this.action,
  });

  final Widget identity;
  final Widget status;
  final Widget books;
  final Widget shelf;
  final Widget checked;
  final Widget action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 4, child: identity),
      const SizedBox(width: Spacing.md),
      SizedBox(width: MediaQuery.textScalerOf(context).scale(180), child: status),
      const SizedBox(width: Spacing.md),
      SizedBox(width: 64, child: books),
      const SizedBox(width: Spacing.md),
      Expanded(flex: 2, child: shelf),
      const SizedBox(width: Spacing.md),
      SizedBox(width: 136, child: checked),
      SizedBox(width: MediaQuery.textScalerOf(context).scale(160), child: action),
    ],
  );
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.folder,
    required this.busy,
    required this.wide,
    required this.showDivider,
    required this.onAction,
  });

  final WatchedFolder folder;
  final bool busy;
  final bool wide;
  final bool showDivider;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<WatchedFolders>();
    final store = context.watch<DataStore>();
    final count = folders.bookIds(folder.id).where((id) => store.getBook(id) != null).length;
    final shelf = folder.shelfId == null ? null : store.getShelf(folder.shelfId!);
    final shelfMissing = folder.shelfId != null && shelf == null;
    final shelfName = shelfMissing ? 'Unavailable' : shelf?.name ?? 'No shelf';
    final theme = Theme.of(context);
    final action = switch (folder.status) {
      _ when !folder.grant.persistent => ('Select again', 'select'),
      FolderStatus.accessNeeded => ('Reconnect', 'reconnect'),
      _ when shelfMissing => ('Choose shelf', 'edit'),
      FolderStatus.paused => ('Resume', 'pause'),
      FolderStatus.attention => ('Review', 'review'),
      _ => null,
    };
    final identity = FolderIdentity(folder: folder, titleStyle: theme.textTheme.titleMedium);
    final status = FolderStatusLabel(
      folder: folder,
      shelfMissing: shelfMissing,
      alignment: wide ? Alignment.centerLeft : Alignment.topLeft,
      reserveHeight: wide,
    );
    final books = Text(
      '$count',
      style: theme.textTheme.bodyMedium,
      semanticsLabel: '$count books in library',
    );
    final actionStyle = theme.textTheme.labelLarge!;
    final actionHeight = math.max(
      TouchTargets.mobileRecommended,
      MediaQuery.textScalerOf(context).scale(actionStyle.fontSize!) * (actionStyle.height ?? 1.4) * 2,
    );
    final actionButton = SizedBox(
      height: actionHeight,
      child: action == null
          ? null
          : FilledButton(
              onPressed: busy ? null : () => onAction(action.$2),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, TouchTargets.mobileRecommended),
                padding: EdgeInsets.symmetric(horizontal: wide ? Spacing.buttonPaddingHorizontal : Spacing.sm),
              ),
              child: Text(action.$1, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
    );

    return Column(
      children: [
        if (showDivider) const Divider(height: 1),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: busy ? null : () => onAction('details'),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: wide
                  ? _FolderColumns(
                      identity: identity,
                      status: status,
                      books: books,
                      shelf: Tooltip(
                        message: shelfName,
                        child: Text(shelfName, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      checked: Text(
                        folderLastChecked(folder, includeLabel: false),
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      action: Align(alignment: Alignment.centerRight, child: actionButton),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: identity),
                            const SizedBox(width: Spacing.sm),
                            SizedBox(width: 128, child: actionButton),
                          ],
                        ),
                        const SizedBox(height: Spacing.md),
                        _FolderSummary(
                          status: status,
                          books: books,
                          shelf: Text(shelfName),
                          checked: Text(folderLastChecked(folder, includeLabel: false)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        FolderProgressBar(folder: folder),
      ],
    );
  }
}

class _FolderSummary extends StatelessWidget {
  const _FolderSummary({required this.status, required this.books, required this.shelf, required this.checked});

  final Widget status;
  final Widget books;
  final Widget shelf;
  final Widget checked;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final textScale = MediaQuery.textScalerOf(context);
      final columns = switch (constraints.maxWidth) {
        final width when width >= textScale.scale(680) => 4,
        final width when width >= textScale.scale(300) => 2,
        _ => 1,
      };
      final fields = [('Status', status), ('Books', books), ('Destination shelf', shelf), ('Last checked', checked)];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < fields.length; start += columns) ...[
            if (start > 0) const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = start; index < start + columns; index++) ...[
                  if (index > start) const SizedBox(width: Spacing.md),
                  Expanded(
                    flex: columns == 2 && index.isEven ? 3 : 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fields[index].$1,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: Spacing.xs),
                        DefaultTextStyle(
                          style: theme.textTheme.bodyMedium!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: fields[index].$2,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );
}
