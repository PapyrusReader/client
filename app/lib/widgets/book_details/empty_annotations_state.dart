import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';

/// Empty state widget for when a book has no annotations.
class EmptyAnnotationsState extends StatelessWidget {
  final bool isPhysical;
  final VoidCallback? onAddAnnotation;

  const EmptyAnnotationsState({super.key, this.isPhysical = false, this.onAddAnnotation});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      alignment: Alignment.topCenter,
      icon: Icons.highlight_outlined,
      title: 'No annotations yet',
      subtitle: isPhysical
          ? 'Add passages you\'ve highlighted or underlined in your book.'
          : 'Highlight text while reading to create annotations.',
      action: isPhysical
          ? EmptyStateAction(onPressed: onAddAnnotation, icon: Icons.add, label: 'Add annotation')
          : null,
    );
  }
}
