import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/add_book/connect_folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_details_sheet.dart';
import 'package:papyrus/widgets/folders/folder_table.dart';
import 'package:papyrus/widgets/folders/edit_folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_issues_sheet.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/folders/folder_sheet.dart';
import 'package:papyrus/widgets/shared/app_drawer.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:provider/provider.dart';

class WatchedFoldersPage extends StatefulWidget {
  const WatchedFoldersPage({super.key});

  @override
  State<WatchedFoldersPage> createState() => _WatchedFoldersPageState();
}

class _WatchedFoldersPageState extends State<WatchedFoldersPage> {
  bool _picking = false;
  String? _actionError;
  String? _errorScope;

  Future<void> _run(Future<void> Function() action) async {
    final folders = context.read<WatchedFolders>();
    final scope = folders.scope;
    setState(() {
      _actionError = null;
      _errorScope = scope;
    });

    try {
      await action();
    } catch (error) {
      if (mounted && folders.scope == scope) {
        setState(() => _actionError = '$error');
      }
    }
  }

  Future<void> _pick({WatchedFolder? replacing}) async {
    if (replacing == null) {
      setState(() => _picking = true);

      try {
        await connectBookFolder(context);
      } finally {
        if (mounted) {
          setState(() => _picking = false);
        }
      }

      return;
    }

    final folders = context.read<WatchedFolders>();
    final scope = folders.scope;
    setState(() => _picking = true);
    FolderGrant? grant;
    var connected = false;

    try {
      grant = await folders.access.pick();

      if (grant == null || !mounted || scope != folders.scope) {
        return;
      }

      await folders.replaceGrant(replacing, grant);
      connected = true;
    } finally {
      if (grant != null && !connected) {
        await folders.access.release(grant);
      }

      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<WatchedFolders>();
    final error = _errorScope == folders.scope ? _actionError ?? folders.error : folders.error;
    final desktop = MediaQuery.sizeOf(context).width >= Breakpoints.desktopSmall;
    final padding = libraryPageHorizontalPadding(context);
    final empty = folders.folders.isEmpty;
    final label = folders.supportsWatching ? 'Connect folder' : 'Import folder';
    final onConnect = folders.ready && !_picking ? () => _run(() => _pick()) : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              Padding(
                padding: EdgeInsets.fromLTRB(padding, Spacing.lg, padding, Spacing.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: TouchTargets.desktopRecommended),
                  child: LibraryToolbar(
                    search: Text('Folders', style: Theme.of(context).textTheme.headlineSmall),
                    actions: [if (!empty) LibraryAddButton(label: label, onPressed: onConnect)],
                  ),
                ),
              )
            else
              LibraryMobileToolbar(
                search: Text('Folders', style: Theme.of(context).textTheme.titleLarge),
                onMenuPressed: () => openAppDrawer(context, Scaffold.maybeOf(context)),
              ),
            if (error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: Spacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            if (!folders.ready)
              const Expanded(
                child: Center(child: AppCircularProgressIndicator(semanticsLabel: 'Loading folders')),
              )
            else if (empty)
              Expanded(
                child: EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'Books from your folders',
                  subtitle: folders.supportsWatching
                      ? 'Connect a folder to add its books and discover new ones while Papyrus is open.'
                      : 'Import books from a folder on this device.',
                  action: EmptyStateAction(label: label, icon: Icons.add, onPressed: onConnect),
                ),
              )
            else ...[
              Expanded(
                child: FolderTable(
                  folders: folders.folders,
                  busy: _picking || !folders.ready,
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, desktop ? Spacing.lg : Spacing.fabClearance),
                  onAction: (folder, action) => _run(() => _action(folder, action)),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: !desktop && !empty && folders.ready
          ? FloatingActionButton(onPressed: onConnect, tooltip: label, child: const Icon(Icons.add))
          : null,
    );
  }

  Future<void> _action(WatchedFolder folder, String action) async {
    final folders = context.read<WatchedFolders>();

    switch (action) {
      case 'details':
        final next = await showFolderSheet<String>(context, builder: (_) => FolderDetailsSheet(folder: folder));

        if (next != null && mounted && folders.folders.contains(folder)) {
          await _action(folder, next);
        }
      case 'edit':
        await showFolderSheet<void>(context, builder: (_) => EditFolderSheet(folder: folder));
      case 'books':
        final library = context.read<LibraryProvider>();
        library.applyFilters(library.filters.copyWith(folderIds: {folder.id}));
        context.go('/library/books');
      case 'scan':
        await folders.scanNow(folder.id);
      case 'pause':
        await folders.update(folder, enabled: !folder.enabled);
      case 'retry':
        await folders.retry(folder);
      case 'reconnect':
        if (!folder.grant.persistent) {
          await _pick(replacing: folder);
          return;
        }

        try {
          await folders.reconnect(folder);
        } on FolderAccessException {
          if (mounted) {
            await showDialog<void>(
              context: context,
              animationStyle: AppMotion.animationStyle(context),
              builder: (dialogContext) => AlertDialog(
                title: const Text('Select this folder again'),
                content: const Text(
                  'Access could not be restored. Select the source folder to reconnect it. Your imported books are safe.',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _run(() => _pick(replacing: folder));
                    },
                    child: const Text('Choose folder'),
                  ),
                ],
              ),
            );
          }
        }
      case 'select':
        await _pick(replacing: folder);
      case 'review':
        await showFolderSheet<void>(
          context,
          builder: (_) => FolderIssuesSheet(folder: folder, folders: folders),
        );
      case 'stop':
        final confirmed = await showDialog<bool>(
          context: context,
          animationStyle: AppMotion.animationStyle(context),
          builder: (context) => AlertDialog(
            title: const Text('Stop watching this folder?'),
            content: const Text('Imported books stay in your library. Pending imports from this folder will stop.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop watching')),
            ],
          ),
        );

        if (confirmed == true && mounted && folders.folders.contains(folder)) {
          await folders.stop(folder);
        }
    }
  }
}
