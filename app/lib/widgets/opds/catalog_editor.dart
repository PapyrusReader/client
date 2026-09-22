import 'package:flutter/material.dart';
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/acquisition/guarded_bottom_sheet_route.dart';
import 'package:papyrus/widgets/opds/opds_sheet.dart';
import 'package:uuid/uuid.dart';

class CatalogEditor extends StatefulWidget {
  const CatalogEditor({super.key, required this.catalogs, this.catalog}) : _busy = null;
  const CatalogEditor._({required this.catalogs, this.catalog, required ValueNotifier<bool> busy}) : _busy = busy;
  final OpdsCatalogs catalogs;
  final OpdsCatalog? catalog;
  final ValueNotifier<bool>? _busy;

  static Future<void> show(BuildContext context, {required OpdsCatalogs catalogs, OpdsCatalog? catalog}) async {
    final busy = ValueNotifier(false);
    try {
      await showGuardedModalBottomSheet<void>(
        context: context,
        busy: busy,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
        builder: (_) => CatalogEditor._(catalogs: catalogs, catalog: catalog, busy: busy),
      );
    } finally {
      busy.dispose();
    }
  }

  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.catalog?.name);
  late final _url = TextEditingController(text: widget.catalog?.uri.toString());
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final String? _scope;
  bool _clearCredentials = false;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scope = widget.catalogs.scope;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    widget._busy?.value = true;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_scope != widget.catalogs.scope) {
        throw const OpdsException('The active account changed. Close this editor and try again.');
      }
      final uri = OpdsHttpClient.validateUri(Uri.parse(_url.text.trim()));
      final changedOrigin = widget.catalog != null && widget.catalog!.uri.origin != uri.origin;
      final credentials = !_clearCredentials && _username.text.isNotEmpty
          ? OpdsCredentials(username: _username.text, password: _password.text)
          : null;
      await widget.catalogs.save(
        OpdsCatalog(id: widget.catalog?.id ?? const Uuid().v4(), name: _name.text.trim(), uri: uri),
        credentials: credentials,
        clearCredentials: _clearCredentials || changedOrigin,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = opdsErrorMessage(error);
        });
      }
    } finally {
      widget._busy?.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: OpdsSheet(
      title: widget.catalog == null ? 'Add catalog' : 'Edit catalog',
      cancelLabel: 'Cancel',
      onSave: _save,
      canSave: !_saving,
      canCancel: !_saving,
      saveLabel: _saving ? 'Saving…' : 'Save',
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('opds-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('opds-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Catalog URL', hintText: 'https://example.com/opds'),
              validator: (value) {
                try {
                  OpdsHttpClient.validateUri(Uri.parse(value?.trim() ?? ''));
                  return null;
                } catch (_) {
                  return 'Enter an HTTP(S) URL without credentials';
                }
              },
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('opds-username'),
              controller: _username,
              enabled: !_clearCredentials,
              decoration: const InputDecoration(labelText: 'Username (optional)'),
              validator: (value) => value != null && value.contains(':') ? 'Username cannot contain a colon' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('opds-password'),
              controller: _password,
              obscureText: true,
              enabled: !_clearCredentials,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) => !_clearCredentials && (value?.isNotEmpty ?? false) && _username.text.isEmpty
                  ? 'Enter a username too'
                  : null,
            ),
            if (widget.catalog != null) ...[
              const SizedBox(height: Spacing.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remove saved credentials'),
                value: _clearCredentials,
                onChanged: _saving ? null : (value) => setState(() => _clearCredentials = value!),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    ),
  );
}
