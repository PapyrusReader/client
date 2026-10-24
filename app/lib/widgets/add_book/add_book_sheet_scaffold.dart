import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';

/// Lays out an add-book sheet with fixed header and footer regions.
class AddBookSheetScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget body;
  final Widget footer;
  final bool canClose;
  final EdgeInsetsGeometry? footerPadding;

  const AddBookSheetScaffold({
    super.key,
    required this.title,
    required this.onClose,
    required this.body,
    required this.footer,
    this.canClose = true,
    this.footerPadding,
  });

  @override
  Widget build(BuildContext context) {
    final fitContent = context.findAncestorWidgetOfExactType<ExpandableBottomSheet>() != null;
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactHeight = constraints.maxHeight < 280;
        final verticalPadding = isCompactHeight ? 0.0 : Spacing.md;

        Widget accessibleChrome(Widget child) => MediaQuery.textScalerOf(context).scale(16) > 32
            ? Flexible(child: SingleChildScrollView(primary: false, child: child))
            : child;

        return Column(
          mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
          children: [
            accessibleChrome(
              BottomSheetHeader(
                key: const Key('add-book-sheet-header'),
                title: title,
                onDismiss: canClose ? onClose : null,
                compact: isCompactHeight,
              ),
            ),
            const Divider(height: 1),
            Flexible(fit: fitContent ? FlexFit.loose : FlexFit.tight, child: body),
            accessibleChrome(
              Container(
                key: const Key('add-book-sheet-footer'),
                padding: footerPadding ?? EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: verticalPadding),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                ),
                child: SafeArea(top: false, child: footer),
              ),
            ),
          ],
        );
      },
    );
  }
}
