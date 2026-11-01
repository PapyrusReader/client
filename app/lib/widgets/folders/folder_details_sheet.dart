import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/folders/folder_identity.dart';
import 'package:papyrus/widgets/folders/edit_folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_status.dart';
import 'package:papyrus/widgets/folders/folder_progress_bar.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:provider/provider.dart';

class FolderDetailsSheet extends StatefulWidget {
  const FolderDetailsSheet({super.key, required this.folder});

  final WatchedFolder folder;

  @override
  State<FolderDetailsSheet> createState() => _FolderDetailsSheetState();
}

class _FolderDetailsSheetState extends State<FolderDetailsSheet> {
  late final String? _scope = context.read<WatchedFolders>().scope;
  bool _busy = false;
  bool _scanning = false;
  String? _error;

  Future<void> _pause() async {
    final folders = context.read<WatchedFolders>();

    if (_scope != folders.scope || !folders.folders.contains(widget.folder)) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await folders.update(widget.folder, enabled: !widget.folder.enabled);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _action(String action) async {
    final folders = context.read<WatchedFolders>();

    if (_scope != folders.scope || !folders.folders.contains(widget.folder)) {
      return;
    }

    switch (action) {
      case 'edit':
        await showFolderSheet<void>(context, builder: (_) => EditFolderSheet(folder: widget.folder));
      case 'pause':
        await _pause();
      default:
        Navigator.pop(context, action);
    }
  }

  Future<void> _scan() async {
    final folders = context.read<WatchedFolders>();

    if (_scanning || _scope != folders.scope || !folders.folders.contains(widget.folder)) {
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      await folders.scanNow(widget.folder.id);
    } catch (error) {
      if (mounted && _scope == folders.scope) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<WatchedFolders>();
    final store = context.watch<DataStore>();
    final uploads = context.watch<MediaUploadQueue>();
    final guest = context.watch<AuthProvider>().isOfflineMode;
    final folder = widget.folder;
    final active = _scope == folders.scope && folders.folders.contains(folder);
    final enabled = active && folders.ready && !_busy;
    final working = folder.status == FolderStatus.scanning || folder.status == FolderStatus.importing;
    final ids = folders.bookIds(folder.id);
    final count = ids.where((id) => store.getBook(id) != null).length;
    final pending = uploads.pendingTasks
        .where((task) => ids.contains(task.bookId))
        .map((task) => task.bookId)
        .toSet()
        .length;
    final shelf = folder.shelfId == null ? null : store.getShelf(folder.shelfId!);
    final shelfMissing = folder.shelfId != null && shelf == null;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final recovery = switch (folder.status) {
      _ when !folder.grant.persistent => ('Select again', 'select'),
      FolderStatus.accessNeeded || FolderStatus.unavailable => ('Reconnect', 'reconnect'),
      _ when shelfMissing => ('Choose shelf', 'edit'),
      FolderStatus.attention => ('Review files', 'review'),
      _ => null,
    };
    final buttonStyle = ButtonStyle(
      shape: theme.outlinedButtonTheme.style?.shape,
      minimumSize: const WidgetStatePropertyAll(Size(0, TouchTargets.mobileRecommended)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm)),
    );

    return FolderSheet(
      title: folder.name,
      canClose: !_busy,
      contentPadding: const EdgeInsets.all(Spacing.md),
      header: Row(
        children: [
          Expanded(child: FolderIdentity(folder: folder)),
          const SizedBox(width: Spacing.sm),
          PopupMenuButton<String>(
            tooltip: '${folder.name} options',
            enabled: enabled,
            popUpAnimationStyle: AppMotion.animationStyle(context),
            onSelected: _action,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit folder')),
              if (folder.grant.persistent)
                PopupMenuItem(value: 'pause', child: Text(folder.enabled ? 'Pause watching' : 'Resume watching')),
              const PopupMenuItem(value: 'review', child: Text('Review files')),
              if (folder.status == FolderStatus.attention)
                const PopupMenuItem(value: 'retry', child: Text('Retry failed imports')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'stop',
                child: Text('Stop watching', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!active)
            const Text('This folder is no longer available in the selected library.')
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: theme.cardTheme.shape ?? const RoundedRectangleBorder(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: Spacing.md,
                    runSpacing: Spacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FolderStatusLabel(folder: folder, shelfMissing: shelfMissing),
                      if (recovery != null)
                        TextButton(
                          onPressed: enabled ? () => _action(recovery.$2) : null,
                          child: Text(recovery.$1),
                        ),
                    ],
                  ),
                  if (folder.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: Text(folder.error!, style: secondary),
                    ),
                ],
              ),
            ),
            FolderProgressBar(folder: folder),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                FilledButton.icon(
                  style: buttonStyle,
                  onPressed: enabled ? () => Navigator.pop(context, 'books') : null,
                  icon: const Icon(Icons.menu_book_outlined, size: IconSizes.small),
                  label: Text('View $count ${count == 1 ? 'book' : 'books'}'),
                ),
                if (folder.grant.persistent)
                  OutlinedButton.icon(
                    style: buttonStyle,
                    onPressed: enabled && !working && !_scanning && folder.enabled ? _scan : null,
                    icon: const Icon(Icons.refresh, size: IconSizes.small),
                    label: const Text('Scan now'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            const Divider(height: 1),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.sm,
              children: [
                _FolderProperty(
                  label: 'Destination shelf',
                  value: shelfMissing ? 'Unavailable' : shelf?.name ?? 'No shelf',
                ),
                _FolderProperty(label: 'Subfolders', value: folder.recursive ? 'Included' : 'Excluded'),
                _FolderProperty(
                  label: 'Last successful check',
                  value: folderLastChecked(folder, includeLabel: false),
                ),
              ],
            ),
            if (!guest && pending > 0) ...[
              const SizedBox(height: Spacing.sm),
              Text('$pending waiting to upload', style: secondary),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: Spacing.md),
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ],
      ),
      footer: BottomSheetActions(
        primary: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
      ),
    );
  }
}

class _FolderProperty extends StatelessWidget {
  const _FolderProperty({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicWidth(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.xs),
            SelectableText(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
