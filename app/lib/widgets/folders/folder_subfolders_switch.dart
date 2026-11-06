import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

class FolderSubfoldersSwitch extends StatelessWidget {
  const FolderSubfoldersSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Include subfolders'),
        value: value,
        onChanged: onChanged,
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? null : Colors.transparent,
        ),
      ),
    ),
  );
}
