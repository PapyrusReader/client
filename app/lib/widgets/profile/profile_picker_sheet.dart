import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';

/// Displays a modal bottom sheet picker for profile preferences.
void showProfilePickerSheet(
  BuildContext context, {
  required List<(String label, String value)> items,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  showModalBottomSheet(
    sheetAnimationStyle: AppMotion.animationStyle(context),
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final colorScheme = Theme.of(sheetContext).colorScheme;
          final isSelected = selected == item.$2;
          return ListTile(
            title: Text(item.$1),
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? colorScheme.primary : colorScheme.outline,
            ),
            onTap: () {
              onSelected(item.$2);
              Navigator.pop(sheetContext);
            },
          );
        }).toList(),
      ),
    ),
  );
}
