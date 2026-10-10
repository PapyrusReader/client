import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';
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
    final route = ModalRoute.of(context);
    final canDismiss = canClose && route is ModalBottomSheetRoute && route.enableDrag;
    final dismiss = canDismiss ? onClose ?? () => Navigator.of(context).maybePop() : null;

    Widget buildFrame(ScrollController? controller, {required bool compact}) => SafeArea(
      top: false,
      bottom: footer == null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BottomSheetHeader(
            key: headerKey ?? const Key('bottom-sheet-header'),
            title: header == null ? title : null,
            onDismiss: dismiss,
            compact: compact,
            child: header,
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
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: avoidKeyboard ? MediaQuery.viewInsetsOf(context).bottom : 0),
      child: LayoutBuilder(
        builder: (context, constraints) => expandable
            ? ExpandableBottomSheet(
                canClose: canClose && (ModalRoute.of(context) as ModalBottomSheetRoute).enableDrag,
                builder: (context, controller) => buildFrame(controller, compact: constraints.maxHeight < 280),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (mobile ? 1 : .9)),
                child: buildFrame(null, compact: constraints.maxHeight < 280),
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
    this.equalWidths = false,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final String saveLabel;
  final String cancelLabel;
  final Key? saveButtonKey;
  final bool equalWidths;

  @override
  Widget build(BuildContext context) => BottomSheetActions(
    equalWidths: equalWidths,
    secondary: OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
    primary: FilledButton(key: saveButtonKey, onPressed: onSave, child: Text(saveLabel)),
  );
}
