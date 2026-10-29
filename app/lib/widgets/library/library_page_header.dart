import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

/// Matches collection content and filter rows to the toolbar's page margins.
double libraryPageHorizontalPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.desktopSmall ? Spacing.lg : AppPageToolbar.padding.left;

/// Page identity and contextual actions for nested Library routes.
class LibraryPageHeader extends StatelessWidget {
  const LibraryPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.compact = false,
    this.dividerKey,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool compact;
  final Key? dividerKey;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return AppPageToolbar(
        leading: leading,
        content: Text(title, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
        actions: actions,
      );
    }

    final heading = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Spacing.sm)],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ComponentSizes.appBarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (actions.isEmpty) {
                  return heading;
                }

                final actionGroup = Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                );

                if (constraints.maxWidth < Breakpoints.tablet || MediaQuery.textScalerOf(context).scale(1) > 1.4) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: Spacing.sm),
                      Align(alignment: Alignment.centerRight, child: actionGroup),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: Spacing.md),
                    actionGroup,
                  ],
                );
              },
            ),
          ),
        ),
        Divider(key: dividerKey, height: 1),
      ],
    );
  }
}

/// Mobile navigation, search and actions in one row.
class LibraryMobileToolbar extends StatelessWidget {
  const LibraryMobileToolbar({super.key, required this.onMenuPressed, this.search, this.actions = const []});

  final VoidCallback onMenuPressed;
  final Widget? search;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AppPageToolbar(
    leading: IconButton(
      icon: const Icon(Icons.menu),
      onPressed: onMenuPressed,
      tooltip: 'Library sections',
    ),
    content: search,
    actions: actions,
  );
}

/// A compact desktop toolbar; the sidebar supplies the collection's name.
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({super.key, this.search, this.actions = const []});

  final Widget? search;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return search ?? const SizedBox.shrink();
    }

    final actionGroup = Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );

    if (search == null) {
      return Align(alignment: Alignment.centerRight, child: actionGroup);
    }

    return LayoutBuilder(
      builder: (context, constraints) => _LibraryToolbarScope(
        compactActions: constraints.maxWidth < Breakpoints.tablet || MediaQuery.textScalerOf(context).scale(1) > 1.4,
        child: Row(
          children: [
            Expanded(child: search!),
            const SizedBox(width: Spacing.md),
            actionGroup,
          ],
        ),
      ),
    );
  }
}

class _LibraryToolbarScope extends InheritedWidget {
  const _LibraryToolbarScope({required this.compactActions, required super.child});

  final bool compactActions;

  @override
  bool updateShouldNotify(_LibraryToolbarScope oldWidget) => compactActions != oldWidget.compactActions;
}

/// The primary creation action shared by Library collection toolbars.
class LibraryAddButton extends StatelessWidget {
  const LibraryAddButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final compact = context.dependOnInheritedWidgetOfExactType<_LibraryToolbarScope>()?.compactActions ?? false;

    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, TouchTargets.desktopRecommended),
      padding: EdgeInsets.symmetric(horizontal: compact ? Spacing.sm : Spacing.md, vertical: Spacing.sm),
      visualDensity: VisualDensity.standard,
    );

    if (compact) {
      return Tooltip(
        message: label,
        child: FilledButton(
          onPressed: onPressed,
          style: style,
          child: Icon(Icons.add, size: IconSizes.medium, semanticLabel: label),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: IconSizes.medium),
      label: Text(label),
      style: style,
    );
  }
}
