import 'package:papyrus/widgets/shared/sheet_choice_buttons.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/collection_grid_density.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

/// Shared grid/list and column controls for Library collections.
Future<void> showCollectionViewSheet(
  BuildContext context,
  CollectionViewControls controls, {
  VoidCallback? onChanged,
}) {
  final changes = Listenable.merge([controls, controls.gridAvailableWidth]);

  void changeGridItemWidth(double width) {
    controls.gridDensity.width = width;
    onChanged?.call();
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    builder: (context) => AnimatedBuilder(
      animation: changes,
      builder: (context, _) {
        final availableWidth = controls.gridAvailableWidth.value;
        final columns = collectionGridLayout(availableWidth, itemWidth: controls.gridDensity.width).crossAxisCount;
        final options = collectionGridSizeOptions(availableWidth);

        return AppBottomSheet(
          header: Text('View mode'),
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
                selected: {controls.viewMode},
                onSelectionChanged: (selection) {
                  controls.setViewMode(selection.single);
                  onChanged?.call();
                },
              ),
              if (controls.viewMode == LibraryViewMode.grid) ...[
                const SizedBox(height: Spacing.lg),
                _ColumnSlider(columns: columns, options: options, onChanged: changeGridItemWidth),
              ],
            ],
          ),
        );
      },
    ),
  );
}

String _columnCountLabel(int columns) => '$columns ${columns == 1 ? 'column' : 'columns'}';

class _ColumnSlider extends StatelessWidget {
  const _ColumnSlider({required this.columns, required this.options, required this.onChanged});

  final int columns;
  final List<CollectionGridSizeOption> options;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexWhere((option) => option.columns == columns);
    final lastIndex = options.length - 1;
    final canAdjust = lastIndex > 0;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget buildSlider({FocusNode? focusNode}) => Slider(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      value: selectedIndex.toDouble(),
      max: lastIndex.toDouble(),
      divisions: canAdjust ? lastIndex : null,
      focusNode: focusNode,
      semanticFormatterCallback: (value) => _columnCountLabel(options[value.round()].columns),
      onChanged: canAdjust ? (value) => onChanged(options[value.round()].preferredWidth) : null,
    );

    final slider = AppMotion.disabled(context)
        ? AppMotionControl(
            value: null,
            enabled: canAdjust,
            builder: (focusNode) => Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _InstantColumnTrack(
                    selectedIndex: selectedIndex,
                    lastIndex: lastIndex,
                    colors: colors,
                    textDirection: Directionality.of(context),
                  ),
                ),
                // Keep the native slider's gestures and semantics. Its thumb
                // animates internally, so reduced motion draws its position above.
                Opacity(opacity: 0, alwaysIncludeSemantics: true, child: buildSlider(focusNode: focusNode)),
              ],
            ),
          )
        : buildSlider();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('Columns', style: theme.textTheme.titleSmall)),
              const SizedBox(width: Spacing.sm),
              Text('$columns', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: 'Columns',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                inactiveTrackColor: colors.outline,
                inactiveTickMarkColor: colors.surface,
                activeTickMarkColor: colors.onPrimary,
              ),
              child: SizedBox(
                height: kMinInteractiveDimension,
                child: slider,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InstantColumnTrack extends CustomPainter {
  const _InstantColumnTrack({
    required this.selectedIndex,
    required this.lastIndex,
    required this.colors,
    required this.textDirection,
  });

  final int selectedIndex;
  final int lastIndex;
  final ColorScheme colors;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    const thumbRadius = 10.0;
    final isRtl = textDirection == TextDirection.rtl;
    final start = isRtl ? size.width - thumbRadius : thumbRadius;
    final end = isRtl ? thumbRadius : size.width - thumbRadius;
    final centerY = size.height / 2;
    final canAdjust = lastIndex > 0;
    Offset position(int index) => Offset(canAdjust ? start + (end - start) * index / lastIndex : start, centerY);

    final activeColor = canAdjust ? colors.primary : colors.onSurface.withValues(alpha: 0.38);
    final inactiveColor = canAdjust ? colors.outline : colors.onSurface.withValues(alpha: 0.12);
    final thumb = position(selectedIndex);
    final trackPaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(start, centerY), Offset(end, centerY), trackPaint);
    canvas.drawLine(Offset(start, centerY), thumb, trackPaint..color = activeColor);

    if (canAdjust) {
      final tickPaint = Paint();

      for (var index = 0; index <= lastIndex; index++) {
        tickPaint.color = index < selectedIndex ? colors.onPrimary : colors.surface;
        canvas.drawCircle(position(index), 0.75, tickPaint);
      }
    }

    canvas.drawCircle(thumb, thumbRadius, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(_InstantColumnTrack oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex ||
      lastIndex != oldDelegate.lastIndex ||
      colors != oldDelegate.colors ||
      textDirection != oldDelegate.textDirection;
}
