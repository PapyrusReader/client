import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/expandable_bottom_sheet.dart';

/// A compact title and handle, with the whole header available for dragging.
class BottomSheetHeader extends StatelessWidget {
  const BottomSheetHeader({super.key, this.title, this.child, this.onDismiss, this.compact = false})
    : assert((title == null) != (child == null));

  final String? title;
  final Widget? child;
  final VoidCallback? onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.tablet;
    final titleStyle = mobile || compact
        ? textTheme.titleMedium?.copyWith(height: 1.5)
        : textTheme.titleLarge?.copyWith(height: 1.25);

    return BottomSheetDragRegion(
      onDismiss: onDismiss,
      child: Semantics(
        onDismiss: onDismiss,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: compact ? 0 : Spacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BottomSheetHandle(),
              const SizedBox(height: Spacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Semantics(
                  header: true,
                  child: DefaultTextStyle.merge(style: titleStyle, child: child ?? Text(title!)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
