import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';

/// Shared sheet framing, with independently scrollable content and fixed actions.
/// Custom headers retain their own typography and controls.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    this.title,
    this.header,
    this.onClose,
    this.canClose = true,
    required this.body,
    this.footer,
    this.scrollable = true,
    this.expandBody = false,
    this.expandOnScroll = true,
    this.avoidKeyboard = true,
    this.contentPadding = const EdgeInsets.all(Spacing.lg),
    this.headerKey,
    this.footerKey,
  }) : assert(title != null || header != null);

  final String? title;
  final Widget? header;
  final VoidCallback? onClose;
  final bool canClose;
  final Widget body;
  final Widget? footer;
  final bool scrollable;
  final bool expandBody;
  final bool expandOnScroll;
  final bool avoidKeyboard;
  final EdgeInsetsGeometry contentPadding;
  final Key? headerKey;
  final Key? footerKey;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
    final expandable = mobile && expandOnScroll && ModalRoute.of(context) is ModalBottomSheetRoute;
    Widget buildFrame(ScrollController? controller, double availableHeight) => SafeArea(
      top: false,
      bottom: footer == null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight =
              // A short, content-sized sheet still needs normal header spacing.
              // Compress only when the available viewport is actually small.
              availableHeight < 280 || (MediaQuery.textScalerOf(context).scale(16) > 20 && availableHeight < 600);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: headerKey ?? const Key('bottom-sheet-header'),
                padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: compactHeight ? 0 : Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BottomSheetHandle(),
                    SizedBox(height: compactHeight ? Spacing.xs : Spacing.lg),
                    header ??
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title!,
                                maxLines: compactHeight ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            if (onClose != null)
                              IconButton(
                                tooltip: 'Close',
                                onPressed: canClose ? onClose : null,
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                fit: expandBody ? FlexFit.tight : FlexFit.loose,
                child: scrollable
                    ? SingleChildScrollView(controller: controller, padding: contentPadding, child: body)
                    : Padding(padding: contentPadding, child: body),
              ),
              if (footer != null) BottomSheetFooter(key: footerKey, child: footer!),
            ],
          );
        },
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: avoidKeyboard ? MediaQuery.viewInsetsOf(context).bottom : 0),
      child: LayoutBuilder(
        builder: (context, constraints) => expandable
            ? ExpandableBottomSheet(
                canClose: canClose && (ModalRoute.of(context) as ModalBottomSheetRoute).enableDrag,
                builder: (context, controller) => buildFrame(controller, constraints.maxHeight),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (mobile ? 1 : .9)),
                child: buildFrame(null, constraints.maxHeight),
              ),
      ),
    );
  }
}

/// A full-width divider and safe-area-aware footer matching the import sheet.
class BottomSheetFooter extends StatelessWidget {
  const BottomSheetFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    ),
    child: SafeArea(top: false, child: child),
  );
}

/// Common cancel/save controls. Labels, disabled states, and callbacks stay local.
class BottomSheetFormActions extends StatelessWidget {
  const BottomSheetFormActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
    this.saveButtonKey,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final String saveLabel;
  final String cancelLabel;
  final Key? saveButtonKey;

  @override
  Widget build(BuildContext context) => BottomSheetActions(
    secondary: OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
    primary: FilledButton(key: saveButtonKey, onPressed: onSave, child: Text(saveLabel)),
  );
}
