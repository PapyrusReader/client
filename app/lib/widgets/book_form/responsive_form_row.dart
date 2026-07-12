import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Responsive row that lays out children horizontally on desktop and
/// vertically on mobile. Used in book forms.
class ResponsiveFormRow extends StatelessWidget {
  final bool isDesktop;
  final List<Widget> children;

  const ResponsiveFormRow({super.key, required this.isDesktop, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAsRow = isDesktop && children.length > 1 && constraints.maxWidth >= Breakpoints.tablet;

        if (!showAsRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children.expand((widget) sync* {
              yield widget;
              yield const SizedBox(height: Spacing.md);
            }).toList()..removeLast(),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children.expand((widget) sync* {
            yield Expanded(child: widget);
            yield const SizedBox(width: Spacing.md);
          }).toList()..removeLast(),
        );
      },
    );
  }
}
