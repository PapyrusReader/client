import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/providers/shelves_provider.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/widgets/library/collection_filter_row.dart';
import 'package:papyrus/widgets/library/collection_view_sheet.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

typedef _ShelfSortSelection = ({ShelfSortOption option, bool ascending});

bool _isEinkTheme(ThemeData theme) {
  final border = theme.inputDecorationTheme.border;

  return border is OutlineInputBorder &&
      border.borderRadius == BorderRadius.zero &&
      border.borderSide.width >= BorderWidths.einkDefault;
}

class _ChipEntry {
  final String id;
  final bool isActive;
  final int defaultOrder;
  final Widget child;

  const _ChipEntry({required this.id, required this.isActive, required this.defaultOrder, required this.child});
}

class _SelectionOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const _SelectionOption({required this.value, required this.label, this.icon});
}

class _DropdownFilterChip extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final IconData icon;
  final bool isSelected;
  final String? tooltip;
  final VoidCallback onPressed;

  const _DropdownFilterChip({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEink = _isEinkTheme(theme);
    final foregroundColor = isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$semanticLabel: $label',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 0),
        child: AppMotionControl(
          value: null,
          builder: (focusNode) => ActionChip(
            focusNode: focusNode,
            chipAnimationStyle: appChipAnimationStyle(context),
            tooltip: tooltip,
            avatar: Icon(icon, size: 18, color: foregroundColor),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: foregroundColor),
              ],
            ),
            labelStyle: TextStyle(color: foregroundColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
            backgroundColor: isSelected ? colorScheme.secondaryContainer : colorScheme.surfaceContainerLow,
            side: BorderSide(
              color: isSelected ? Colors.transparent : colorScheme.outlineVariant,
              width: isEink ? BorderWidths.einkDefault : BorderWidths.thin,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isEink ? AppRadius.none : AppRadius.full),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _SingleSelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<_SelectionOption<T>> options;
  final T selectedValue;

  const _SingleSelectionSheet({required this.title, required this.options, required this.selectedValue});

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      header: Text(title),
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      body: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: options.length,
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option.value == selectedValue;

          return Semantics(
            selected: isSelected,
            child: ListTile(
              selected: isSelected,
              leading: option.icon == null ? null : Icon(option.icon),
              title: Text(option.label),
              trailing: isSelected ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(option.value),
            ),
          );
        },
      ),
    );
  }
}

Future<T?> _showSingleSelectionSheet<T>(
  BuildContext context, {
  required String title,
  required List<_SelectionOption<T>> options,
  required T selectedValue,
}) {
  return showModalBottomSheet<T>(
    sheetAnimationStyle: AppMotion.animationStyle(context),
    context: context,
    useSafeArea: true,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => _SingleSelectionSheet<T>(title: title, options: options, selectedValue: selectedValue),
  );
}

class ShelvesFilterChips extends StatelessWidget {
  final double? horizontalPadding;

  const ShelvesFilterChips({super.key, this.horizontalPadding});

  static const List<_SelectionOption<ShelfContentsFilter>> _contentsOptions = [
    _SelectionOption(value: ShelfContentsFilter.all, label: 'Any'),
    _SelectionOption(value: ShelfContentsFilter.withBooks, label: 'With books', icon: Icons.auto_stories_outlined),
    _SelectionOption(value: ShelfContentsFilter.empty, label: 'Empty', icon: Icons.inventory_2_outlined),
  ];

  static const List<_SelectionOption<ShelfTypeFilter>> _typeOptions = [
    _SelectionOption(value: ShelfTypeFilter.all, label: 'Any'),
    _SelectionOption(value: ShelfTypeFilter.regular, label: 'Regular', icon: Icons.shelves),
    _SelectionOption(value: ShelfTypeFilter.smart, label: 'Smart', icon: Icons.auto_awesome_outlined),
  ];

  static const List<_SelectionOption<_ShelfSortSelection>> _sortOptions = [
    _SelectionOption(value: (option: ShelfSortOption.name, ascending: true), label: 'Name (A-Z)'),
    _SelectionOption(value: (option: ShelfSortOption.name, ascending: false), label: 'Name (Z-A)'),
    _SelectionOption(value: (option: ShelfSortOption.bookCount, ascending: true), label: 'Book count (Ascending)'),
    _SelectionOption(value: (option: ShelfSortOption.bookCount, ascending: false), label: 'Book count (Descending)'),
    _SelectionOption(value: (option: ShelfSortOption.dateCreated, ascending: false), label: 'Date created (newest)'),
    _SelectionOption(value: (option: ShelfSortOption.dateCreated, ascending: true), label: 'Date created (oldest)'),
    _SelectionOption(value: (option: ShelfSortOption.dateModified, ascending: false), label: 'Date modified (newest)'),
    _SelectionOption(value: (option: ShelfSortOption.dateModified, ascending: true), label: 'Date modified (oldest)'),
  ];

  @override
  Widget build(BuildContext context) {
    final isEink = _isEinkTheme(Theme.of(context));
    final provider = context.watch<ShelvesProvider>();
    final selectedContents = _optionFor(_contentsOptions, provider.contentsFilter);
    final selectedType = _optionFor(_typeOptions, provider.typeFilter);
    final selectedSortValue = (option: provider.shelfSortOption, ascending: provider.shelfSortAscending);
    final selectedSort = _optionFor(_sortOptions, selectedSortValue);

    final chips = <_ChipEntry>[
      _ChipEntry(
        id: 'contents',
        defaultOrder: 0,
        isActive: provider.contentsFilter != ShelfContentsFilter.all,
        child: _DropdownFilterChip(
          label: provider.contentsFilter == ShelfContentsFilter.all ? 'Contents' : selectedContents.label,
          semanticLabel: 'Shelf contents',
          icon: Icons.auto_stories_outlined,
          isSelected: provider.contentsFilter != ShelfContentsFilter.all,
          tooltip: 'Filter by shelf contents',
          onPressed: () => _selectSingle<ShelfContentsFilter>(
            context: context,
            title: 'Shelf contents',
            options: _contentsOptions,
            selectedValue: provider.contentsFilter,
            onSelected: provider.setContentsFilter,
          ),
        ),
      ),
      _ChipEntry(
        id: 'sort',
        defaultOrder: 1,
        isActive: provider.shelfSortOption != ShelfSortOption.name || !provider.shelfSortAscending,
        child: _DropdownFilterChip(
          label: selectedSort.label,
          semanticLabel: 'Shelf sorting',
          icon: Icons.sort_rounded,
          isSelected: provider.shelfSortOption != ShelfSortOption.name || !provider.shelfSortAscending,
          tooltip: 'Sort shelves',
          onPressed: () => _selectSingle<_ShelfSortSelection>(
            context: context,
            title: 'Sort shelves',
            options: _sortOptions,
            selectedValue: selectedSortValue,
            onSelected: (selection) => provider.setShelfSortOption(selection.option, ascending: selection.ascending),
          ),
        ),
      ),
      _ChipEntry(
        id: 'type',
        defaultOrder: 2,
        isActive: provider.typeFilter != ShelfTypeFilter.all,
        child: _DropdownFilterChip(
          label: provider.typeFilter == ShelfTypeFilter.all ? 'Type' : selectedType.label,
          semanticLabel: 'Shelf type',
          icon: Icons.shelves,
          isSelected: provider.typeFilter != ShelfTypeFilter.all,
          tooltip: 'Filter by shelf type',
          onPressed: () => _selectSingle<ShelfTypeFilter>(
            context: context,
            title: 'Shelf type',
            options: _typeOptions,
            selectedValue: provider.typeFilter,
            onSelected: provider.setTypeFilter,
          ),
        ),
      ),
      _ChipEntry(
        id: 'view',
        defaultOrder: 3,
        isActive: provider.viewMode != LibraryViewMode.grid,
        child: _DropdownFilterChip(
          label: provider.viewMode.label,
          semanticLabel: 'View mode',
          icon: provider.viewMode == LibraryViewMode.grid ? Icons.grid_view : Icons.view_list,
          isSelected: provider.viewMode != LibraryViewMode.grid,
          tooltip: 'Change view mode',
          onPressed: () => showCollectionViewSheet(context, provider),
        ),
      ),
    ];

    chips.sort((left, right) {
      final viewComparison = (right.id == 'view' ? 1 : 0).compareTo(left.id == 'view' ? 1 : 0);

      if (viewComparison != 0) {
        return viewComparison;
      }

      final activeComparison = (right.isActive ? 1 : 0).compareTo(left.isActive ? 1 : 0);
      return activeComparison != 0 ? activeComparison : left.defaultOrder.compareTo(right.defaultOrder);
    });

    return CollectionFilterRow(
      chips: [for (final chip in chips) (id: chip.id, child: chip.child)],
      height: TouchTargets.mobileRecommended,
      gridAvailableWidth: provider.gridAvailableWidth,
      horizontalPadding: horizontalPadding,
      onClear: provider.hasActiveShelfControls ? provider.clearShelfControls : null,
      clearButtonShape: isEink ? const RoundedRectangleBorder() : null,
    );
  }

  Future<void> _selectSingle<T>({
    required BuildContext context,
    required String title,
    required List<_SelectionOption<T>> options,
    required T selectedValue,
    required ValueChanged<T> onSelected,
  }) async {
    final result = await _showSingleSelectionSheet<T>(
      context,
      title: title,
      options: options,
      selectedValue: selectedValue,
    );

    if (result == null || result == selectedValue) {
      return;
    }

    onSelected(result);
  }

  static _SelectionOption<T> _optionFor<T>(List<_SelectionOption<T>> options, T selectedValue) {
    return options.firstWhere((option) => option.value == selectedValue);
  }
}
