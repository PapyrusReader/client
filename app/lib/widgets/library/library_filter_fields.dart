import 'package:flutter/material.dart';
import 'package:papyrus/models/library_filters.dart';
import 'package:papyrus/models/library_filter_options.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';

bool isLibraryFilterEinkTheme(ThemeData theme) {
  final border = theme.inputDecorationTheme.border;

  return border is OutlineInputBorder &&
      border.borderRadius == BorderRadius.zero &&
      border.borderSide.width >= BorderWidths.einkDefault;
}

class LibraryControlGroup extends StatelessWidget {
  final String label;
  final String? summary;
  final Widget child;

  const LibraryControlGroup({super.key, required this.label, this.summary, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              if (summary != null) ...[
                const SizedBox(width: Spacing.sm),
                Text(summary!, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

Widget _selectionChip(
  BuildContext context, {
  required String label,
  required bool isSelected,
  required VoidCallback onSelected,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isEink = isLibraryFilterEinkTheme(theme);

  return AppMotionControl(
    value: null,
    builder: (focusNode) => FilterChip(
      focusNode: focusNode,
      chipAnimationStyle: appChipAnimationStyle(context),
      label: Text(label),
      selected: isSelected,
      showCheckmark: true,
      checkmarkColor: colorScheme.onSecondaryContainer,
      side: BorderSide(
        color: isSelected ? Colors.transparent : colorScheme.outlineVariant,
        width: isEink ? BorderWidths.einkDefault : BorderWidths.thin,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isEink ? AppRadius.none : AppRadius.md)),
      backgroundColor: Colors.transparent,
      selectedColor: colorScheme.secondaryContainer,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onSelected(),
    ),
  );
}

class LibrarySmallFacet<T> extends StatelessWidget {
  final String label;
  final bool showSummary;
  final List<LibraryFilterOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onChanged;

  const LibrarySmallFacet({
    super.key,
    required this.label,
    this.showSummary = true,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LibraryControlGroup(
      label: label,
      summary: showSummary ? (selectedValues.isEmpty ? 'Any' : '${selectedValues.length} selected') : null,
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final option in options)
            Builder(
              builder: (context) {
                final isSelected = selectedValues.contains(option.value);

                return _selectionChip(
                  context,
                  label: option.label,
                  isSelected: isSelected,
                  onSelected: () {
                    final values = Set<T>.of(selectedValues);

                    if (!values.add(option.value)) {
                      values.remove(option.value);
                    }

                    onChanged(values);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class LibraryFavoriteFilterField extends StatelessWidget {
  final FavoriteFilter value;
  final ValueChanged<FavoriteFilter> onChanged;

  const LibraryFavoriteFilterField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget choiceChip(String label, FavoriteFilter filter) {
      final isSelected = value == filter;
      return _selectionChip(context, label: label, isSelected: isSelected, onSelected: () => onChanged(filter));
    }

    return LibraryControlGroup(
      label: 'Favorite state',
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          choiceChip('Any', FavoriteFilter.any),
          choiceChip('Favorites', FavoriteFilter.favorites),
          choiceChip('Not favorites', FavoriteFilter.notFavorites),
        ],
      ),
    );
  }
}

class LibraryProgressFilterField extends StatefulWidget {
  final LibraryProgressRange? value;
  final ValueChanged<LibraryProgressRange?> onChanged;

  const LibraryProgressFilterField({super.key, required this.value, required this.onChanged});

  @override
  State<LibraryProgressFilterField> createState() => LibraryProgressFilterFieldState();
}

class LibraryProgressFilterFieldState extends State<LibraryProgressFilterField> {
  RangeValues get _values {
    final value = widget.value;
    return value == null ? const RangeValues(0, 100) : RangeValues(value.start * 100, value.end * 100);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = widget.value != null;
    final values = _values;
    final summary = isEnabled ? '${values.start.round()}% – ${values.end.round()}%' : 'Any';

    void toggleEnabled() {
      widget.onChanged(isEnabled ? null : const LibraryProgressRange(0, 1));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Semantics(
            container: true,
            toggled: isEnabled,
            label: 'Progress percentage, $summary',
            onTap: toggleEnabled,
            excludeSemantics: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                excludeFromSemantics: true,
                onTap: toggleEnabled,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Progress percentage', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              summary,
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      ExcludeFocus(
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: AppMotionControl(
                              value: isEnabled,
                              builder: (focusNode) =>
                                  Switch(focusNode: focusNode, value: isEnabled, onChanged: (_) => toggleEnabled()),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isEnabled)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: RangeSlider(
                values: values,
                min: 0,
                max: 100,
                padding: EdgeInsets.zero,
                divisions: 20,
                labels: RangeLabels('${values.start.round()}%', '${values.end.round()}%'),
                onChanged: (range) {
                  widget.onChanged(LibraryProgressRange(range.start / 100, range.end / 100));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class LibraryRatingFilterField extends StatelessWidget {
  final Set<int> ratings;
  final bool includeUnrated;
  final List<int> availableRatings;
  final bool showUnrated;
  final void Function(Set<int> ratings, bool includeUnrated) onChanged;

  const LibraryRatingFilterField({
    super.key,
    required this.ratings,
    required this.includeUnrated,
    required this.availableRatings,
    required this.showUnrated,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LibraryControlGroup(
      label: 'Rating',
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          if (showUnrated)
            _selectionChip(
              context,
              label: 'Unrated',
              isSelected: includeUnrated,
              onSelected: () => onChanged(ratings, !includeUnrated),
            ),
          for (final rating in availableRatings)
            Builder(
              builder: (context) {
                final isSelected = ratings.contains(rating);

                return _selectionChip(
                  context,
                  label: List.filled(rating, '★').join(),
                  isSelected: isSelected,
                  onSelected: () {
                    final values = Set<int>.of(ratings);

                    if (!values.add(rating)) {
                      values.remove(rating);
                    }

                    onChanged(values, includeUnrated);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class LibraryDateRangeField extends StatelessWidget {
  final String label;
  final LibraryDateRange? value;
  final ValueChanged<LibraryDateRange?> onChanged;

  const LibraryDateRangeField({super.key, required this.label, required this.value, required this.onChanged});

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();

    final selectedRange = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(1000),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDateRange: value == null ? null : DateTimeRange(start: value!.start, end: value!.end),
    );

    if (selectedRange != null) {
      onChanged(LibraryDateRange(selectedRange.start, selectedRange.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEink = isLibraryFilterEinkTheme(theme);
    final localizations = MaterialLocalizations.of(context);
    final value = this.value;

    final summary = value == null
        ? 'Any'
        : '${localizations.formatCompactDate(value.start)} – ${localizations.formatCompactDate(value.end)}';

    final borderRadius = BorderRadius.circular(isEink ? AppRadius.none : AppRadius.sm);

    final pickerBorderRadius = value == null
        ? borderRadius
        : BorderRadius.horizontal(left: Radius.circular(isEink ? AppRadius.none : AppRadius.sm));

    void pickRange() {
      _pickRange(context);
    }

    return LibraryControlGroup(
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: isEink ? BorderWidths.einkDefault : BorderWidths.thin,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Select $label, $summary',
                  onTap: pickRange,
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: pickerBorderRadius,
                    excludeFromSemantics: true,
                    onTap: pickRange,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 54),
                      child: Padding(
                        padding: const EdgeInsets.only(left: Spacing.md),
                        child: Row(
                          children: [
                            Expanded(child: Text(summary)),
                            if (value == null) const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (value != null)
                IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  tooltip: 'Clear $label',
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
