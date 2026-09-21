import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';

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
  EdgeInsetsGeometry contentPadding = const EdgeInsets.all(Spacing.md),
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

/// A bounded sheet with a fixed header and a keyboard-safe scrollable body.
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
    this.contentPadding = const EdgeInsets.all(Spacing.md),
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
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
                child: Column(
                  children: [
                    const BottomSheetHandle(),
                    const SizedBox(height: Spacing.sm),
                    LayoutBuilder(
                      builder: (context, constraints) => BottomSheetHeader(
                        stacked: constraints.maxWidth < 400 && MediaQuery.textScalerOf(context).scale(16) > 16 * 1.4,
                        title: title,
                        onCancel: () => Navigator.of(context).pop(),
                        onSave: onSave,
                        saveLabel: saveLabel,
                        cancelLabel: cancelLabel,
                        canSave: canSave,
                        canCancel: canCancel,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: scrollable
                    ? SingleChildScrollView(padding: contentPadding, child: child)
                    : Padding(padding: contentPadding, child: child),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
