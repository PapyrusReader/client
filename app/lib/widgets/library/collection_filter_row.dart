import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

class CollectionFilterRow extends StatelessWidget {
  const CollectionFilterRow({
    super.key,
    required this.chips,
    required this.height,
    required this.gridAvailableWidth,
    this.horizontalPadding,
    this.onClear,
    this.clearButtonShape,
  });

  final List<({String id, Widget child})> chips;
  final double height;
  final ValueNotifier<double> gridAvailableWidth;
  final double? horizontalPadding;
  final VoidCallback? onClear;
  final OutlinedBorder? clearButtonShape;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(horizontal: horizontalPadding ?? Spacing.md);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - padding.horizontal).clamp(0.0, double.infinity);

        if (gridAvailableWidth.value != width) {
          // The open sheet is in the root overlay, outside this layout pass.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              gridAvailableWidth.value = width;
            }
          });
        }

        return _buildRow(context, padding);
      },
    );
  }

  Widget _buildRow(BuildContext context, EdgeInsets padding) {
    final entries = [
      if (onClear != null)
        (
          id: 'clear-all',
          child: Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: onClear,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, TouchTargets.mobileMin),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: clearButtonShape,
              ),
              icon: const Icon(Icons.filter_alt_off_outlined, size: IconSizes.small),
              label: const Text('Clear all'),
            ),
          ),
        ),
      ...chips,
    ];

    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        key: ValueKey(AppMotion.disabled(context)),
        duration: AppMotion.duration(context, AnimationDurations.standard),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(animation);

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(alignment: Alignment.centerLeft, children: [...previousChildren, ?currentChild]);
        },
        child: ListView.separated(
          key: ValueKey(entries.map((entry) => entry.id).join('-')),
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return KeyedSubtree(key: ValueKey(entry.id), child: entry.child);
          },
        ),
      ),
    );
  }
}
