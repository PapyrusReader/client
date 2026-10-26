import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyrus/themes/app_accessibility.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

/// The client owns panel presentation; the reader supplies live panel content.
Route<void> buildReaderPanelRoute(
  BuildContext context,
  ReaderPanelRouteContext panel, {
  String? bookTitle,
  bool showTitle = true,
}) {
  final navigator = Navigator.of(context);
  final theme = Theme.of(context);
  final localizations = MaterialLocalizations.of(context);

  if (panel.kind == ReaderPanelKind.tableOfContents) {
    final capturedThemes = InheritedTheme.capture(from: context, to: navigator.context);

    return MaterialPageRoute<void>(
      builder: (context) => capturedThemes.wrap(
        ReaderSystemTextScope(
          child: Builder(
            builder: (context) => CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  appBar: AppPageBar(
                    context: context,
                    leading: const BackButton(),
                    title: Text(bookTitle ?? panel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  body: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showTitle)
                          Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(panel.title, style: Theme.of(context).textTheme.titleMedium),
                          ),
                        if (showTitle) const Divider(height: 1),
                        Expanded(child: panel.buildContent(context, null)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    builder: (context) => ReaderSystemTextScope(
      child: AppBottomSheet(
        title: panel.title,
        contentPadding: EdgeInsets.zero,
        scrollBodyBuilder: panel.buildContent,
      ),
    ),
  );
}
