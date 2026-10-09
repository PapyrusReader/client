import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

/// Single-choice controls that wrap when a segmented row would be too crowded.
class SheetChoiceButtons<T> extends StatelessWidget {
  const SheetChoiceButtons({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 480 && MediaQuery.textScalerOf(context).scale(16) <= 20) {
        return SegmentedButton<T>(
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        );
      }

      return Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final segment in segments)
            AppMotionControl(
              value: selected.contains(segment.value),
              enabled: segment.enabled,
              builder: (focusNode) => ChoiceChip(
                focusNode: focusNode,
                chipAnimationStyle: appChipAnimationStyle(context),
                avatar: segment.icon,
                label: segment.label ?? const SizedBox.shrink(),
                selected: selected.contains(segment.value),
                onSelected: segment.enabled ? (_) => onSelectionChanged({segment.value}) : null,
              ),
            ),
        ],
      );
    },
  );
}
