import 'package:papyrus/widgets/shared/sheet_choice_buttons.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/widgets/library/book_grid_layout.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

Future<void> showLibraryViewSheet(
  BuildContext context,
  LibraryProvider provider, {
  required double availableWidth,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (context) => AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final columns = bookGridLayout(availableWidth, itemWidth: provider.gridItemWidth).crossAxisCount;
        final options = bookGridSizeOptions(availableWidth);

        return AppBottomSheet(
          header: Text('View mode', style: Theme.of(context).textTheme.titleLarge),
          footer: BottomSheetActions(
            primary: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetChoiceButtons<LibraryViewMode>(
                segments: const [
                  ButtonSegment(value: LibraryViewMode.grid, icon: Icon(Icons.grid_view), label: Text('Grid')),
                  ButtonSegment(value: LibraryViewMode.list, icon: Icon(Icons.view_list), label: Text('List')),
                ],
                selected: {provider.viewMode},
                onSelectionChanged: (selection) {
                  provider.setViewMode(selection.single);
                  onChanged?.call();
                },
              ),
              if (provider.viewMode == LibraryViewMode.grid) ...[
                const SizedBox(height: 24),
                Text('Columns', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final option in options)
                      AppMotionControl(
                        value: columns == option.columns,
                        builder: (focusNode) => ChoiceChip(
                          focusNode: focusNode,
                          chipAnimationStyle: appChipAnimationStyle(context),
                          label: Text('${option.columns} ${option.columns == 1 ? 'column' : 'columns'}'),
                          selected: columns == option.columns,
                          onSelected: (_) {
                            provider.setGridItemWidth(option.preferredWidth);
                            onChanged?.call();
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
