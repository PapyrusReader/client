import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Shared sizing for actions on local and catalog book details.
ButtonStyle bookDetailsActionStyle(BuildContext context, {bool iconOnly = false}) => ButtonStyle(
  visualDensity: VisualDensity.standard,
  shape: const WidgetStatePropertyAll(StadiumBorder()),
  minimumSize: WidgetStatePropertyAll(Size(iconOnly ? 48 : 0, 48)),
  textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15)),
  iconSize: const WidgetStatePropertyAll(20),
  padding: WidgetStatePropertyAll(
    iconOnly ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20, vertical: Spacing.sm),
  ),
);
