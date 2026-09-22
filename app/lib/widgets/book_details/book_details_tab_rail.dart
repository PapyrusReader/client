import 'package:flutter/material.dart';

/// Common tab rail for local and catalog book details.
class BookDetailsTabRail extends StatelessWidget {
  const BookDetailsTabRail({super.key, this.controller, required this.tabs});

  final TabController? controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) => TabBar(
    controller: controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Theme.of(context).colorScheme.outlineVariant,
    tabs: tabs,
  );
}
