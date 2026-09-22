import 'package:flutter/material.dart';

/// Shared loading presentation for library and remote catalog artwork.
class CoverLoadingPlaceholder extends StatelessWidget {
  const CoverLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Loading book cover',
      child: Container(
        key: const Key('cover-image-loading'),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 72 || constraints.maxHeight < 96;
            final icon = Icon(
              Icons.auto_stories_rounded,
              size: compact ? 22 : 36,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            );
            if (compact) return Center(child: icon);

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(height: 8),
                  Text(
                    'Loading…',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
