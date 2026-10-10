import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

/// The client owns sheet presentation; the reader supplies live panel content.
Route<void> buildReaderPanelSheet(BuildContext context, ReaderPanelRouteContext panel) {
  final navigator = Navigator.of(context);
  final theme = Theme.of(context);
  final localizations = MaterialLocalizations.of(context);

  return ModalBottomSheetRoute<void>(
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
    modalBarrierColor: theme.bottomSheetTheme.modalBarrierColor,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    shape:
        theme.bottomSheetTheme.shape ??
        const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    clipBehavior: Clip.antiAlias,
    builder: (context) => AppBottomSheet(
      title: panel.title,
      contentPadding: EdgeInsets.zero,
      scrollBodyBuilder: panel.buildContent,
    ),
  );
}
