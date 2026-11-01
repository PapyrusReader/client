import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

/// Contextual header shown when selection mode is active.
/// Replaces the normal library header with close, count, select all, and actions.
class SelectionHeader extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final Widget? actions;
  final bool compact;

  const SelectionHeader({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onClose,
    required this.onSelectAll,
    required this.onDeselectAll,
    this.actions,
    this.compact = false,
  });

  bool get _allSelected => selectedCount >= totalCount && totalCount > 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final close = IconButton(icon: const Icon(Icons.close), tooltip: 'Exit selection', onPressed: onClose);

    final selectAll = TextButton(
      onPressed: _allSelected ? onDeselectAll : onSelectAll,
      child: Text(_allSelected ? 'Deselect all' : 'Select all', maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    final selectionControls = Row(
      children: [
        if (!compact) ...[close, const SizedBox(width: Spacing.sm)],
        Flexible(
          child: Text(
            '$selectedCount selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: Spacing.md),
        compact ? Flexible(child: selectAll) : selectAll,
      ],
    );

    if (compact) {
      return AppPageToolbar(leading: close, content: selectionControls, actions: [?actions]);
    }

    return Row(
      children: [
        Expanded(child: selectionControls),
        if (actions != null) ...[
          const SizedBox(width: Spacing.md),
          actions!,
        ],
      ],
    );
  }
}
