import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 280;
              final verticalPadding = compactHeight ? 0.0 : Spacing.md;
              void close() => Navigator.of(context).pop();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    key: const Key('opds-sheet-header'),
                    padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: verticalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BottomSheetHandle(),
                        SizedBox(height: compactHeight ? 0 : Spacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: compactHeight ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: canCancel ? close : null,
                              icon: const Icon(Icons.close),
                            ),
                          ],
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
                  Container(
                    key: const Key('opds-sheet-footer'),
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: verticalPadding),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Spacing.md,
                      runSpacing: Spacing.sm,
                      children: [
                        TextButton(onPressed: canCancel ? close : null, child: Text(cancelLabel)),
                        if (onSave != null) FilledButton(onPressed: canSave ? onSave : null, child: Text(saveLabel)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
