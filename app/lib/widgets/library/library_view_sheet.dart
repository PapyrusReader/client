import 'package:papyrus/widgets/shared/sheet_choice_buttons.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/models/book_grid_size.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_motion.dart';

Future<void> showLibraryViewSheet(BuildContext context, LibraryProvider provider, {VoidCallback? onChanged}) {
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
        final width = provider.gridItemWidth;
        void resize(double value) {
          provider.setGridItemWidth(value);
          onChanged?.call();
        }

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
                Text('Cover size', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Smaller covers',
                      onPressed: width > BookGridSize.minimum ? () => resize(width - BookGridSize.step) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        value: width,
                        min: BookGridSize.minimum,
                        max: BookGridSize.maximum,
                        divisions: ((BookGridSize.maximum - BookGridSize.minimum) / BookGridSize.step).round(),
                        semanticFormatterCallback: (value) =>
                            'Cover size ${((value - BookGridSize.minimum) / BookGridSize.step).round() + 1} of 11',
                        onChanged: resize,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Larger covers',
                      onPressed: width < BookGridSize.maximum ? () => resize(width + BookGridSize.step) : null,
                      icon: const Icon(Icons.add),
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
