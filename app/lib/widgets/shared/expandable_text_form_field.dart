import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

/// Expanding changes the editing space, not the draft or its save lifecycle.
class ExpandableTextFormField extends StatefulWidget {
  const ExpandableTextFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.minLines,
    this.maxLines = 3,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int? minLines;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  State<ExpandableTextFormField> createState() => _ExpandableTextFormFieldState();
}

class _ExpandableTextFormFieldState extends State<ExpandableTextFormField> {
  final _focusNode = FocusNode();
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_draftChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandableTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_draftChanged);
      widget.controller.addListener(_draftChanged);
    }
  }

  void _draftChanged() {
    if (_fieldKey.currentState?.value != widget.controller.text) {
      _fieldKey.currentState?.didChange(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_draftChanged);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    if (_expanded) {
      return;
    }

    _expanded = true;
    _focusNode.unfocus();

    await showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierDismissible: false,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        },
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppPageBar(
              context: context,
              automaticallyImplyLeading: false,
              title: Text(widget.label),
              actions: [
                IconButton(
                  tooltip: 'Exit full screen',
                  icon: const Icon(Icons.fullscreen_exit),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Breakpoints.desktopSmall),
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: TextField(
                      key: const Key('fullscreen-note-field'),
                      controller: widget.controller,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _expanded = false;

    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: _fieldKey,
    initialValue: widget.controller.text,
    validator: (_) => widget.validator?.call(widget.controller.text),
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                suffixIcon: const SizedBox(width: TouchTargets.mobileRecommended),
                enabledBorder: field.hasError
                    ? OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error))
                    : null,
                focusedBorder: field.hasError
                    ? OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2))
                    : null,
              ),
              textCapitalization: TextCapitalization.sentences,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              textAlignVertical: TextAlignVertical.top,
            ),
            Positioned(
              right: Spacing.xs,
              bottom: Spacing.xs,
              child: IconButton(
                tooltip: 'Edit in full screen',
                icon: const Icon(Icons.fullscreen),
                onPressed: _expand,
              ),
            ),
          ],
        ),
        if (field.errorText case final error?)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, Spacing.xs, 12, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );
}
