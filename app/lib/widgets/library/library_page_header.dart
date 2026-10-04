import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Matches collection content and filter rows to the toolbar's page margins.
double libraryPageHorizontalPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.desktopSmall ? Spacing.lg : Spacing.md;

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
      return SizedBox(
        height: Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight,
        child: AppBar(
          primary: false,
          automaticallyImplyLeading: false,
          leading: leading,
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: actions,
        ),
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
                if (actions.isEmpty) return heading;
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

/// Mobile navigation occupies the search prefix instead of adding a page inset.
class LibraryMobileToolbar extends StatelessWidget {
  const LibraryMobileToolbar({super.key, required this.onMenuPressed, this.searchBuilder, this.actions = const []});

  final VoidCallback onMenuPressed;
  final Widget Function(Widget leading)? searchBuilder;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final menu = IconButton(icon: const Icon(Icons.menu), onPressed: onMenuPressed, tooltip: 'Library sections');
    return Row(
      children: [
        if (searchBuilder != null) Expanded(child: searchBuilder!(menu)) else ...[menu, const Spacer()],
        for (final action in actions) ...[const SizedBox(width: Spacing.sm), action],
      ],
    );
  }
}

/// A compact desktop toolbar; the sidebar supplies the collection's name.
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({super.key, this.search, this.actions = const []});

  final Widget? search;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return search ?? const SizedBox.shrink();
    final actionGroup = Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    if (search == null) return Align(alignment: Alignment.centerRight, child: actionGroup);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.tablet || MediaQuery.textScalerOf(context).scale(1) > 1.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search!,
              const SizedBox(height: Spacing.sm),
              Align(alignment: Alignment.centerRight, child: actionGroup),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search!),
            const SizedBox(width: Spacing.md),
            actionGroup,
          ],
        );
      },
    );
  }
}

/// The primary creation action shared by Library collection toolbars.
class LibraryAddButton extends StatelessWidget {
  const LibraryAddButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.add, size: IconSizes.medium),
    label: Text(label),
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, TouchTargets.desktopRecommended),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      visualDensity: VisualDensity.standard,
    ),
  );
}
