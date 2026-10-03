import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

Future<T?> showOpdsSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  VoidCallback? onSave,
  String saveLabel = 'Save',
  String cancelLabel = 'Close',
  bool canSave = true,
  bool canCancel = true,
  bool scrollable = true,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.all(Spacing.lg),
}) {
  final reduceAnimations = AppMotion.disabled(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (_) => AppMotionScope(
      reduceAnimations: reduceAnimations,
      child: OpdsSheet(
        title: title,
        onSave: onSave,
        saveLabel: saveLabel,
        cancelLabel: cancelLabel,
        canSave: canSave,
        canCancel: canCancel,
        scrollable: scrollable,
        contentPadding: contentPadding,
        child: child,
      ),
    ),
  );
}

/// A keyboard-safe sheet with a fixed title, close control, and action footer.
class OpdsSheet extends StatelessWidget {
  const OpdsSheet({
    super.key,
    required this.title,
    required this.child,
    this.onSave,
    this.saveLabel = 'Save',
    this.cancelLabel = 'Close',
    this.canSave = true,
    this.canCancel = true,
    this.scrollable = true,
    this.contentPadding = const EdgeInsets.all(Spacing.lg),
  });

  final String title;
  final Widget child;
  final VoidCallback? onSave;
  final String saveLabel;
  final String cancelLabel;
  final bool canSave;
  final bool canCancel;
  final bool scrollable;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) => AppBottomSheet(
    title: title,
    headerKey: const Key('opds-sheet-header'),
    footerKey: const Key('opds-sheet-footer'),
    onClose: () => Navigator.of(context).pop(),
    canClose: canCancel,
    scrollable: scrollable,
    contentPadding: contentPadding,
    body: child,
    footer: onSave == null
        ? BottomSheetActions(
            primary: OutlinedButton(
              onPressed: canCancel ? () => Navigator.of(context).pop() : null,
              child: Text(cancelLabel),
            ),
          )
        : BottomSheetFormActions(
            onCancel: canCancel ? () => Navigator.of(context).pop() : null,
            onSave: canSave ? onSave : null,
            saveLabel: saveLabel,
            cancelLabel: cancelLabel,
          ),
  );
}
