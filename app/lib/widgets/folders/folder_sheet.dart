import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

Future<T?> showFolderSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  final reduceAnimations = AppMotion.disabled(context);

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (context) => AppMotionScope(reduceAnimations: reduceAnimations, child: builder(context)),
  );
}

/// Keeps asynchronous folder operations from dismissing their owning sheet.
class FolderSheet extends StatelessWidget {
  const FolderSheet({
    super.key,
    required this.title,
    required this.body,
    required this.footer,
    this.header,
    this.contentPadding = const EdgeInsets.all(Spacing.lg),
    this.canClose = true,
  });

  final String title;
  final Widget body;
  final Widget footer;
  final Widget? header;
  final EdgeInsetsGeometry contentPadding;
  final bool canClose;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canClose,
    child: AppBottomSheet(
      title: title,
      header: header,
      canClose: canClose,
      body: body,
      footer: footer,
      contentPadding: contentPadding,
    ),
  );
}
