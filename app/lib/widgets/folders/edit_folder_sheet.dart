import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/add_book/connect_folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_sheet.dart';
import 'package:papyrus/widgets/folders/folder_location_field.dart';
import 'package:papyrus/widgets/folders/folder_subfolders_switch.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

class EditFolderSheet extends StatefulWidget {
  const EditFolderSheet({super.key, required this.folder});

  final WatchedFolder folder;

  @override
  State<EditFolderSheet> createState() => _EditFolderSheetState();
}

class _EditFolderSheetState extends State<EditFolderSheet> {
  late final String? _scope = context.read<WatchedFolders>().scope;
  late bool _recursive = widget.folder.recursive;
  late String? _shelf = widget.folder.shelfId;
  late final _name = TextEditingController(text: widget.folder.name);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final folders = context.read<WatchedFolders>();

    if (_scope != folders.scope || !folders.folders.contains(widget.folder)) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await folders.update(widget.folder, name: _name.text, recursive: _recursive, shelfId: _shelf, changeShelf: true);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<WatchedFolders>();
    final store = context.watch<DataStore>();
    final active = _scope == folders.scope && folders.folders.contains(widget.folder);
    final enabled = active && folders.ready && !_saving;
    final changed =
        _name.text.trim() != widget.folder.name ||
        _recursive != widget.folder.recursive ||
        _shelf != widget.folder.shelfId;
    final shelfMissing = _shelf != null && store.getShelf(_shelf!) == null;
    final theme = Theme.of(context);

    return FolderSheet(
      title: 'Edit folder',
      canClose: !_saving,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!active)
            const Text('This folder is no longer available in the selected library.')
          else ...[
            FolderLocationField(grant: widget.folder.grant),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _name,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _name.text.trim().isEmpty ? 'Enter a folder name' : null,
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.md),
            FolderShelfPicker(value: _shelf, onChanged: enabled ? (value) => setState(() => _shelf = value) : null),
            if (shelfMissing) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'This shelf was deleted. Choose another shelf or No shelf.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            FolderSubfoldersSwitch(
              value: _recursive,
              onChanged: enabled ? (value) => setState(() => _recursive = value) : null,
            ),
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
      footer: BottomSheetFormActions(
        onCancel: _saving ? null : () => Navigator.pop(context),
        onSave: enabled && changed && _name.text.trim().isNotEmpty ? _save : null,
        saveLabel: _saving ? 'Saving…' : 'Save changes',
      ),
    );
  }
}
