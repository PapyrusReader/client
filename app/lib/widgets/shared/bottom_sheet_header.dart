import 'package:flutter/material.dart';

/// A reusable header row for bottom sheets.
///
/// Renders Cancel (TextButton) on the left, [title] centered, and
/// Save (FilledButton) on the right.
class BottomSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final String saveLabel;
  final Key? saveButtonKey;
  final bool canCancel;
  final bool canSave;
  final String cancelLabel;
  final bool stacked;

  const BottomSheetHeader({
    super.key,
    required this.title,
    required this.onCancel,
    this.onSave,
    this.saveLabel = 'Save',
    this.saveButtonKey,
    this.canCancel = true,
    this.canSave = true,
    this.cancelLabel = 'Cancel',
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
    final cancelButton = TextButton(onPressed: canCancel ? onCancel : null, child: Text(cancelLabel));
    final saveButton = onSave == null
        ? const SizedBox.shrink()
        : FilledButton(key: saveButtonKey, onPressed: canSave ? onSave : null, child: Text(saveLabel));
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleWidget,
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [cancelButton, if (onSave != null) saveButton],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: cancelButton),
        ),
        Expanded(child: titleWidget),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: saveButton),
        ),
      ],
    );
  }
}
