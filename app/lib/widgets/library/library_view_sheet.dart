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
    showDragHandle: true,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: AnimatedBuilder(
          animation: provider,
          builder: (context, _) {
            final width = provider.gridItemWidth;
            void resize(double value) {
              provider.setGridItemWidth(value);
              onChanged?.call();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('View mode', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                SegmentedButton<LibraryViewMode>(
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
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
