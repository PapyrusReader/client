import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';

/// Displays a modal bottom sheet picker for profile preferences.
void showProfilePickerSheet(
  BuildContext context, {
  required String title,
  required List<(String label, String value)> items,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  showModalBottomSheet(
    sheetAnimationStyle: AppMotion.animationStyle(context),
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => AppBottomSheet(
      header: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
      contentPadding: EdgeInsets.zero,
      body: Column(
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
