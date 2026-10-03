import 'package:flutter/material.dart';

/// Lets the book header scroll away while keeping the tab rail above its body.
class BookDetailsScrollView extends StatelessWidget {
  const BookDetailsScrollView({super.key, required this.header, required this.rail, required this.body});

  final Widget header;
  final PreferredSizeWidget rail;
  final Widget body;

  @override
  Widget build(BuildContext context) => NestedScrollView(
    headerSliverBuilder: (context, innerBoxIsScrolled) => [
      SliverToBoxAdapter(child: header),
      // The rail must participate in sliver layout: the header can leave less
      // space than the tabs need, including no visible space at all.
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: PinnedHeaderSliver(
          child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: rail),
        ),
      ),
    ],
    // Reserve the pinned rail outside the tab views so their contents and
    // gestures remain below it even when the inner scroll position changes.
    body: Padding(
      padding: EdgeInsets.only(top: rail.preferredSize.height),
      child: body,
    ),
  );
}
