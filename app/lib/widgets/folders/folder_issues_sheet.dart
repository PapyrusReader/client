import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/folders/folder_sheet.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';

class FolderIssuesSheet extends StatefulWidget {
  const FolderIssuesSheet({super.key, required this.folder, required this.folders});
  final WatchedFolder folder;
  final WatchedFolders folders;

  @override
  State<FolderIssuesSheet> createState() => _FolderIssuesSheetState();
}

class _FolderIssuesSheetState extends State<FolderIssuesSheet> {
  late final String? _scope = widget.folders.scope;
  late Future<List<Map<String, dynamic>>> _issues = widget.folders.issues(widget.folder.id);
  String? _error;
  bool _busy = false;

  Future<void> _review(Map<String, dynamic> record, bool import) async {
    if (_scope != widget.folders.scope) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (record['state'] == 'failed') {
        await widget.folders.retry(widget.folder);
      } else {
        await widget.folders.review(widget.folder, record, import: import);
      }

      if (mounted) {
        setState(() => _issues = widget.folders.issues(widget.folder.id));
      }
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

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<WatchedFolders>();
    final store = context.watch<DataStore>();
    final active = _scope == folders.scope && folders.folders.contains(widget.folder);
    final theme = Theme.of(context);

    return FolderSheet(
      title: 'Review files',
      canClose: !_busy,
      body: !active
          ? const Text('This folder is no longer available in the selected library.')
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _issues,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                }

                final records = snapshot.data;

                if (records == null) {
                  return const Center(child: AppCircularProgressIndicator(semanticsLabel: 'Loading files'));
                }

                if (records.isEmpty) {
                  return const Text('No files need review.');
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    for (final record in records) ...[
                      Text(record['name'] as String? ?? 'Source file', style: theme.textTheme.titleMedium),
                      const SizedBox(height: Spacing.sm),
                      if (record['state'] == 'changed') ...[
                        Text(
                          'In your library: ${store.getBook(record['bookId'] as String? ?? '')?.title ?? 'Previously imported book'}',
                        ),
                        const SizedBox(height: Spacing.xs),
                        const Text(
                          'The source file has changed. Keeping the existing book preserves its reading progress and annotations.',
                        ),
                      ] else
                        Text(
                          record['state'] == 'failed'
                              ? '${record['error']}'
                              : 'Removed from your library. It will not be imported automatically.',
                        ),
                      const SizedBox(height: Spacing.sm),
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: [
                          if (record['state'] == 'changed')
                            TextButton(
                              onPressed: _busy ? null : () => _review(record, false),
                              child: const Text('Keep existing'),
                            ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _review(record, true),
                            child: Text(switch (record['state']) {
                              'changed' => 'Import separately',
                              'failed' => 'Retry',
                              _ => 'Reimport',
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      const Divider(),
                      const SizedBox(height: Spacing.md),
                    ],
                  ],
                );
              },
            ),
      footer: BottomSheetActions(
        primary: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
      ),
    );
  }
}
