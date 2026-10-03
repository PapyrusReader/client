import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';

typedef AcquisitionCommandLabel = String Function(String command);

Future<String?> showAcquisitionCommandSheet({
  required BuildContext context,
  required String endpointName,
  required String endpointKindLabel,
  required List<String> commands,
  required AcquisitionCommandLabel commandLabel,
}) {
  return showModalBottomSheet<String>(
    sheetAnimationStyle: AppMotion.animationStyle(context),
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bottomSheet)),
    ),
    isScrollControlled: true,
    builder: (sheetContext) => AppBottomSheet(
      key: const Key('acquisition-command-sheet'),
      title: endpointName,
      onClose: () => Navigator.of(sheetContext).pop(),
      footer: BottomSheetActions(
        primary: OutlinedButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('Cancel')),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            endpointKindLabel,
            style: Theme.of(
              sheetContext,
            ).textTheme.labelLarge?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.sm),
          for (final command in commands)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow),
              title: Text(commandLabel(command)),
              subtitle: Text(command),
              onTap: () => Navigator.of(sheetContext).pop(command),
            ),
        ],
      ),
    ),
  );
}

Future<List<int>?> showAcquisitionIdsSheet({required BuildContext context, required String title}) {
  var enteredIds = '';

  return showModalBottomSheet<List<int>>(
    sheetAnimationStyle: AppMotion.animationStyle(context),
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bottomSheet)),
    ),
    builder: (sheetContext) => AppBottomSheet(
      key: const Key('acquisition-arr-ids-sheet'),
      title: title,
      onClose: () => Navigator.of(sheetContext).pop(),
      footer: BottomSheetFormActions(
        onCancel: () => Navigator.of(sheetContext).pop(),
        saveLabel: 'Run',
        onSave: () {
          final ids = enteredIds.split(',').map((value) => int.tryParse(value.trim())).whereType<int>().toList();
          Navigator.of(sheetContext).pop(ids);
        },
      ),
      body: TextField(
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'IDs',
          helperText: 'Comma-separated IDs from the Arr application',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => enteredIds = value,
      ),
    ),
  );
}

Future<bool?> showAcquisitionRemoveDialog({required BuildContext context, required String endpointName}) {
  return showDialog<bool>(
    animationStyle: AppMotion.animationStyle(context),
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;

      return AlertDialog(
        title: const Text('Remove integration'),
        content: Text('Remove "$endpointName"? Saved credentials for this integration will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
}
