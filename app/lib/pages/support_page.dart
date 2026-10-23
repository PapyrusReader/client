import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/services/app_info.dart';
import 'package:papyrus/services/support_api_client.dart';
import 'package:papyrus/services/support_attachment.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/profile/support_confirmation.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.client});

  final SupportApiClient client;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _scrollController = ScrollController();
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _kind = 'bug';
  String _version = 'Unavailable';
  final _attachments = <SupportAttachment>[];
  bool _picking = false;
  String? _attachmentError;
  bool _sending = false;
  String? _error;
  SupportIssue? _issue;

  String get _platform => kIsWeb ? 'Web (${defaultTargetPlatform.name})' : defaultTargetPlatform.name;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await loadAppInfo();

      if (mounted) {
        setState(() => _version = AboutLinks.versionLabel(info));
      }
    } catch (_) {
      // A missing version must not prevent the reader from reporting a problem.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _title.dispose();
    _description.dispose();
    widget.client.close();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    if (_picking || _sending) {
      return;
    }

    setState(() {
      _picking = true;
      _attachmentError = null;
    });

    try {
      final attachments = await SupportAttachment.pick(SupportAttachment.maxCount - _attachments.length);

      if (mounted) {
        setState(() => _attachments.addAll(attachments));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _attachmentError = error is FormatException ? error.message : 'Could not attach files.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_sending || _picking || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final issue = await widget.client.submit(
        kind: _kind,
        title: _title.text,
        description: _description.text,
        appVersion: _version,
        platform: _platform,
        attachments: _attachments,
      );

      if (mounted) {
        FocusScope.of(context).unfocus();

        setState(() {
          _issue = issue;
          _attachments.clear();
        });

        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    } on SupportException {
      if (mounted) {
        setState(() => _error = 'Submission failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    final textTheme = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LibraryPageHeader(title: 'Support', leading: const BackButton(), compact: compact),
              if (compact) const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: issue != null
                          ? SupportConfirmation(issue: issue)
                          : Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('How can we help?', style: textTheme.titleLarge),
                                  const SizedBox(height: Spacing.md),
                                  const Text(
                                    'Report a problem or suggest an improvement. Feedback and attachments are public. '
                                    'Do not include passwords, private book content, or other personal information.',
                                  ),
                                  const SizedBox(height: Spacing.lg),
                                  DropdownButtonFormField<String>(
                                    initialValue: _kind,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Request type'),
                                    items: const [
                                      DropdownMenuItem(value: 'bug', child: Text('Bug report')),
                                      DropdownMenuItem(value: 'feature', child: Text('Feature request')),
                                    ],
                                    onChanged: _sending ? null : (value) => setState(() => _kind = value!),
                                  ),
                                  const SizedBox(height: Spacing.md),
                                  TextFormField(
                                    controller: _title,
                                    enabled: !_sending,
                                    maxLength: 150,
                                    decoration: const InputDecoration(labelText: 'Title'),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty ? 'Enter a title.' : null,
                                  ),
                                  const SizedBox(height: Spacing.md),
                                  TextFormField(
                                    controller: _description,
                                    enabled: !_sending,
                                    minLines: 6,
                                    maxLines: 12,
                                    maxLength: 8000,
                                    decoration: InputDecoration(
                                      labelText: 'Description',
                                      alignLabelWithHint: true,
                                      hintText: _kind == 'bug'
                                          ? 'What happened? What did you expect? How can we reproduce it?'
                                          : 'What would you like to do, and how would it help?',
                                    ),
                                    validator: (value) => value == null || value.trim().length < 10
                                        ? 'Please add a little more detail (at least 10 characters).'
                                        : null,
                                  ),
                                  const SizedBox(height: Spacing.md),
                                  OutlinedButton.icon(
                                    onPressed: _sending || _picking || _attachments.length >= SupportAttachment.maxCount
                                        ? null
                                        : _pickAttachments,
                                    icon: const Icon(Icons.attach_file),
                                    label: Text(_picking ? 'Attaching…' : 'Attach images or videos'),
                                  ),
                                  const SizedBox(height: Spacing.xs),
                                  Text('Up to 5 files · 10 MB each', style: textTheme.bodySmall),
                                  for (final attachment in _attachments)
                                    Padding(
                                      padding: const EdgeInsets.only(top: Spacing.sm),
                                      child: Row(
                                        children: [
                                          Icon(attachment.isVideo ? Icons.videocam_outlined : Icons.image_outlined),
                                          const SizedBox(width: Spacing.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(attachment.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                                Text(attachment.sizeLabel, style: textTheme.bodySmall),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Remove ${attachment.name}',
                                            onPressed: _sending || _picking
                                                ? null
                                                : () => setState(() => _attachments.remove(attachment)),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_attachmentError != null) ...[
                                    const SizedBox(height: Spacing.sm),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _attachmentError!,
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ),
                                  ],
                                  if (_error != null) ...[
                                    const SizedBox(height: Spacing.sm),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _error!,
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: Spacing.lg),
                                  FilledButton(
                                    onPressed: _sending || _picking ? null : _submit,
                                    child: Text(_sending ? 'Submitting…' : 'Submit'),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
