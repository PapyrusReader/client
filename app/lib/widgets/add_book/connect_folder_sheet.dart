import 'dart:async';

import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/folders/folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_location_field.dart';
import 'package:papyrus/widgets/folders/folder_subfolders_switch.dart';
import 'package:papyrus/widgets/library/acquisition_status_text.dart' show formatBytes;
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

/// Start picking synchronously with the user's tap, even while the choice sheet closes.
Future<void> connectBookFolder(BuildContext context, {Future<dynamic>? afterDismissal}) async {
  final folders = context.read<WatchedFolders>();
  final scope = folders.scope;
  FolderGrant? grant;
  var connected = false;

  try {
    if (!folders.ready) {
      throw StateError('Wait for your library to finish loading.');
    }

    grant = await folders.access.pick();
    await afterDismissal;

    if (grant == null || !context.mounted || scope != folders.scope) {
      return;
    }

    connected =
        await showFolderSheet<bool>(
          context,
          builder: (_) => ConnectFolderSheet(grant: grant!, folders: folders, scope: scope),
        ) ??
        false;
  } catch (error) {
    await afterDismissal;

    if (context.mounted && scope == folders.scope) {
      await showFolderSheet<void>(
        context,
        builder: (context) => FolderSheet(
          title: 'Could not connect folder',
          body: Text(_folderErrorMessage(error)),
          footer: BottomSheetActions(
            primary: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ),
        ),
      );
    }
  } finally {
    if (grant != null && !connected) {
      await folders.access.release(grant);
    }
  }
}

class ConnectFolderSheet extends StatefulWidget {
  const ConnectFolderSheet({super.key, required this.grant, required this.folders, required this.scope});
  final FolderGrant grant;
  final WatchedFolders folders;
  final String? scope;

  @override
  State<ConnectFolderSheet> createState() => _ConnectFolderSheetState();
}

class _ConnectFolderSheetState extends State<ConnectFolderSheet> {
  late final _name = TextEditingController(text: widget.grant.name);
  bool _recursive = true;
  String? _shelf;
  FolderPreview? _preview;
  String? _error;
  bool _saving = false;
  bool _showScanProgress = false;
  Timer? _scanProgressTimer;
  late Future<void> _pendingScan;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanProgressTimer?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _startScan() {
    _pendingScan = _scan();
  }

  Future<void> _scan() async {
    final revision = ++_revision;
    _scanProgressTimer?.cancel();
    setState(() => _error = null);
    _scanProgressTimer = Timer(AnimationDurations.standard, () {
      if (mounted && revision == _revision) {
        setState(() => _showScanProgress = true);
      }
    });

    try {
      final preview = await widget.folders.preview(
        widget.grant,
        _recursive,
        cancelled: () => !mounted || revision != _revision || widget.scope != widget.folders.scope,
      );

      if (mounted && revision == _revision) {
        _scanProgressTimer?.cancel();
        setState(() {
          _preview = preview;
          _showScanProgress = false;
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        _scanProgressTimer?.cancel();
        setState(() {
          _error = _folderErrorMessage(error);
          _showScanProgress = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      // A quick recheck keeps the action available, but must finish before importing.
      await _pendingScan;

      if (!mounted) {
        return;
      }

      if (_error != null || _preview == null) {
        setState(() => _saving = false);
        return;
      }

      if (widget.scope != widget.folders.scope) {
        throw StateError('The selected library changed. Choose this folder again.');
      }

      await widget.folders.connect(widget.grant, name: _name.text, recursive: _recursive, shelfId: _shelf);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _folderErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondaryStyle = textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant);
    final problemCount = (preview?.unsupported ?? 0) + (preview?.inaccessible ?? 0);
    final canImport =
        !_saving && !_showScanProgress && preview != null && _error == null && _name.text.trim().isNotEmpty;

    return FolderSheet(
      title: widget.grant.persistent ? 'Connect folder' : 'Import folder',
      canClose: !_saving,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
            const SizedBox(height: Spacing.md),
          ],
          FolderLocationField(grant: widget.grant),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _name,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _name.text.trim().isEmpty ? 'Enter a folder name' : null,
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Spacing.md),
          FolderShelfPicker(value: _shelf, onChanged: _saving ? null : (value) => setState(() => _shelf = value)),
          FolderSubfoldersSwitch(
            value: _recursive,
            onChanged: _saving
                ? null
                : (value) {
                    setState(() => _recursive = value);
                    _startScan();
                  },
          ),
          const Divider(height: Spacing.lg),
          SizedBox(
            height: Spacing.xs,
            child: _showScanProgress
                ? const AppLinearProgressIndicator(semanticsLabel: 'Checking folder', minHeight: Spacing.xs)
                : null,
          ),
          Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.sm,
            children: [
              _PreviewValue(label: 'Books found', value: preview?.supported.toString() ?? '—'),
              _PreviewValue(label: 'Total size', value: _previewSize(preview)),
            ],
          ),
          if (preview != null) ...[
            if (preview.unsupported > 0 || preview.inaccessible > 0)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: Spacing.sm),
                title: Text('$problemCount ${problemCount == 1 ? 'file' : 'files'} cannot be imported'),
                children: [
                  if (preview.unsupported > 0) _PreviewProblem(label: 'Unsupported format', count: preview.unsupported),
                  if (preview.inaccessible > 0) _PreviewProblem(label: 'Could not access', count: preview.inaccessible),
                ],
              ),
            if (!widget.grant.persistent) ...[
              const SizedBox(height: Spacing.md),
              Text('Select this folder again to import new books.', style: secondaryStyle),
            ],
          ],
        ],
      ),
      footer: BottomSheetFormActions(
        onCancel: _saving ? null : () => Navigator.pop(context, false),
        onSave: canImport ? _save : null,
        saveLabel: _saving ? 'Importing…' : (widget.grant.persistent ? 'Import and watch' : 'Import books'),
      ),
    );
  }
}

String _folderErrorMessage(Object error) => error is StateError ? error.message : '$error';

String _previewSize(FolderPreview? preview) {
  if (preview == null) {
    return '—';
  }

  if (preview.unknownSizes > 0) {
    return preview.bytes == 0 ? 'Unknown' : 'At least ${formatBytes(preview.bytes)}';
  }

  return formatBytes(preview.bytes);
}

class _PreviewValue extends StatelessWidget {
  const _PreviewValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.xs),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _PreviewProblem extends StatelessWidget {
  const _PreviewProblem({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: Spacing.md),
        Text('$count'),
      ],
    ),
  );
}

class FolderShelfPicker extends StatelessWidget {
  const FolderShelfPicker({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final shelves = context.watch<DataStore>().shelves;

    return DropdownButtonFormField<String>(
      initialValue: shelves.any((shelf) => shelf.id == value) ? value : '',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Destination shelf'),
      items: [
        const DropdownMenuItem(value: '', child: Text('No shelf')),
        for (final shelf in shelves)
          DropdownMenuItem(
            value: shelf.id,
            child: Text(shelf.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null ? null : (value) => onChanged!(value == '' ? null : value),
    );
  }
}
