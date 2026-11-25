import 'package:flutter/material.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/card_overlay_colors.dart';
import 'package:papyrus/widgets/library/acquisition_status_text.dart';
import 'package:papyrus/widgets/library/collection_grid_layout.dart';
import 'package:papyrus/widgets/library/collection_grid_card.dart';
import 'package:papyrus/widgets/library/collection_grid_card_body.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class AcquisitionPlaceholderCard extends StatefulWidget {
  final AcquisitionJob job;
  final VoidCallback? onTap;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onEnterSelectionMode;
  final bool compact;
  final double? transferDetailsLineHeight;

  const AcquisitionPlaceholderCard({
    super.key,
    required this.job,
    this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectToggle,
    this.onEnterSelectionMode,
    this.compact = false,
    this.transferDetailsLineHeight,
  });

  @override
  State<AcquisitionPlaceholderCard> createState() => _AcquisitionPlaceholderCardState();
}

class _AcquisitionPlaceholderCardState extends State<AcquisitionPlaceholderCard> {
  bool _isHovered = false;
  bool _titleFocused = false;

  bool get _isDesktop => MediaQuery.sizeOf(context).width >= Breakpoints.desktopSmall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = acquisitionStatusLabel(widget.job);
    final details = acquisitionTransferDetails(widget.job);
    final effectiveTap = widget.isSelectionMode ? widget.onSelectToggle : widget.onTap;
    final effectiveLongPress = widget.isSelectionMode ? null : widget.onEnterSelectionMode;
    final semanticLabel = <String>[widget.job.title, status, ?details].join('. ');
    final hasInteraction = effectiveTap != null || effectiveLongPress != null;

    return Semantics(
      key: ValueKey('acquisition-placeholder-card-${widget.job.id}'),
      container: true,
      label: semanticLabel,
      button: hasInteraction,
      selected: widget.isSelected,
      onTap: effectiveTap,
      onLongPress: effectiveLongPress,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onLongPress: effectiveLongPress,
                child: CollectionGridCard(
                  child: InkWell(
                    onTap: effectiveTap,
                    onFocusChange: (focused) => setState(() => _titleFocused = focused),
                    child: CollectionGridCardBody(
                      title: widget.job.title,
                      subtitle: status,
                      compact: widget.compact,
                      titleFocused: _titleFocused,
                      subtitleStyle: widget.job.requiresAttention
                          ? TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600)
                          : null,
                      transferDetails: details,
                      transferDetailsLineHeight: widget.transferDetailsLineHeight,
                      progress: widget.job.progress == null
                          ? null
                          : AppLinearProgressIndicator(
                              value: widget.job.progress,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              color: widget.job.requiresAttention ? colorScheme.error : colorScheme.primary,
                              minHeight: collectionGridProgressHeight,
                            ),
                      preview: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.menu_book_outlined,
                              size: widget.compact ? IconSizes.medium : IconSizes.display,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                            ),
                          ),
                          if (widget.isSelectionMode && widget.isSelected)
                            Container(color: colorScheme.primary.withValues(alpha: 0.15)),
                          if (widget.isSelectionMode)
                            Positioned(
                              top: Spacing.xs,
                              right: Spacing.xs,
                              child: _SelectionIconButton(
                                selected: widget.isSelected,
                                onTap: widget.onSelectToggle,
                              ),
                            )
                          else if (_isDesktop)
                            Positioned(
                              top: Spacing.xs,
                              right: Spacing.xs,
                              child: AnimatedOpacity(
                                key: ValueKey(AppMotion.disabled(context)),
                                opacity: _isHovered ? 1 : 0,
                                duration: AppMotion.duration(context, const Duration(milliseconds: 150)),
                                child: _SelectionIconButton(selected: false, onTap: widget.onEnterSelectionMode),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!widget.isSelectionMode && _isDesktop && widget.onEnterSelectionMode != null)
            Positioned(
              top: Spacing.xs,
              right: Spacing.xs,
              child: Semantics(
                key: ValueKey('acquisition-selector-${widget.job.id}'),
                container: true,
                label: 'Select ${widget.job.title}',
                button: true,
                onTap: widget.onEnterSelectionMode,
                child: const ExcludeSemantics(child: SizedBox(width: 32, height: 32)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionIconButton extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;

  const _SelectionIconButton({required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: CardOverlayColors.background,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: IconSizes.small,
            color: selected ? CardOverlayColors.selection(colorScheme) : Colors.white,
          ),
        ),
      ),
    );
  }
}
