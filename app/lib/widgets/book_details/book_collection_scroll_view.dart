import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Keeps collection controls scrollable even when the book header fills the page.
class BookCollectionScrollView extends StatelessWidget {
  const BookCollectionScrollView({
    super.key,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyState,
  });

  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget emptyState;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      PinnedHeaderSliver(
        child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: header),
      ),

      if (itemCount == 0)
        SliverFillRemaining(
          hasScrollBody: false,
          // This message scrolls with the slivers, not a second primary viewport.
          child: PrimaryScrollController.none(child: emptyState),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
          sliver: SliverList.separated(
            itemCount: itemCount,
            itemBuilder: itemBuilder,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          ),
        ),
    ],
  );
}
