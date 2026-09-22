import 'package:flutter/material.dart';

/// Lets the book header scroll away while keeping the tab rail above its body.
class BookDetailsScrollView extends StatelessWidget {
  const BookDetailsScrollView({super.key, required this.header, required this.rail, required this.body});

  final Widget header;
  final Widget rail;
  final Widget body;

  @override
  Widget build(BuildContext context) => NestedScrollView(
    headerSliverBuilder: (context, innerBoxIsScrolled) => [SliverToBoxAdapter(child: header)],
    body: Column(
      children: [
        rail,
        Expanded(child: body),
      ],
    ),
  );
}
