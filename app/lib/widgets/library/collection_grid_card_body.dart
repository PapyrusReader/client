import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';
import 'package:papyrus/widgets/library/collection_grid_title.dart';

/// Shared preview and aligned metadata for tiles in the library grid.
class CollectionGridCardBody extends StatelessWidget {
  const CollectionGridCardBody({
    super.key,
    required this.preview,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.titleFocused = false,
    this.leading,
    this.subtitleStyle,
    this.progress,
    this.transferDetails,
    this.transferDetailsLineHeight,
  });

  final Widget preview;
  final String title;
  final String subtitle;
  final bool compact;
  final bool titleFocused;
  final Widget? leading;
  final TextStyle? subtitleStyle;
  final Widget? progress;
  final String? transferDetails;
  final double? transferDetailsLineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: preview),
        SizedBox(
          height: collectionGridProgressHeight,
          child: progress ?? ColoredBox(color: colors.surfaceContainerHighest),
        ),
        Padding(
          padding: EdgeInsets.all(collectionGridMetadataPadding(compact: compact)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: IconSizes.small),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  heightFactor: 1,
                  child: Row(
                    children: [
                      if (leading case final icon?) ...[icon, const SizedBox(width: Spacing.xs)],
                      Expanded(
                        child: CollectionGridTitle(
                          title: title,
                          style: collectionGridTitleStyle(theme.textTheme, compact: compact),
                          focused:
                              titleFocused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: collectionGridMetadataGap),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant).merge(subtitleStyle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (transferDetails != null || transferDetailsLineHeight != null) ...[
                const SizedBox(height: collectionGridMetadataGap),
                SizedBox(
                  height: transferDetailsLineHeight,
                  child: switch (transferDetails) {
                    final details? => Text(
                      details,
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    null => null,
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
