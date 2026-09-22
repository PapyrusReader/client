import 'package:flutter/material.dart';

/// Standard mobile app bar for every catalog route, inside the page's SafeArea.
class OpdsMobileHeader extends StatelessWidget {
  const OpdsMobileHeader({super.key, required this.title, required this.leading, required this.actions});

  final String title;
  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight,
    child: AppBar(
      primary: false,
      leading: leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      actions: actions,
    ),
  );
}
