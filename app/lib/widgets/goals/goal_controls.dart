import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Content-sized controls for Goals, including sheets opened on the root navigator.
class GoalControls extends StatelessWidget {
  const GoalControls({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, ComponentSizes.buttonHeightMobile)),
      shape: WidgetStatePropertyAll(StadiumBorder()),
    );
    return Theme(
      data: theme.copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(style: compact.merge(theme.outlinedButtonTheme.style)),
        filledButtonTheme: FilledButtonThemeData(style: compact.merge(theme.filledButtonTheme.style)),
        textButtonTheme: TextButtonThemeData(
          style: const ButtonStyle(
            shape: WidgetStatePropertyAll(StadiumBorder()),
            minimumSize: WidgetStatePropertyAll(Size(0, 40)),
          ).merge(theme.textButtonTheme.style),
        ),
      ),
      child: child,
    );
  }
}
