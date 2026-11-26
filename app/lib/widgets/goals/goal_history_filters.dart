import 'package:flutter/material.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';

GoalRange? goalDateRange(DateTimeRange? dates, String timezone) => dates == null
    ? null
    : GoalRange(
        GoalCalendar.dayOffset(GoalCalendar.deadline(dates.start, timezone), -1, timezone),
        GoalCalendar.deadline(dates.end, timezone),
      );

class GoalScopeFilter extends StatelessWidget {
  const GoalScopeFilter({
    super.key,
    required this.definitions,
    required this.selected,
    required this.onChanged,
  });
  final Map<String, ReadingGoal> definitions;
  final ReadingGoal? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - Spacing.xl * 2).clamp(120, 280).toDouble(),
    child: DropdownButtonFormField<String>(
      key: ValueKey(selected?.id),
      initialValue: selected?.id ?? '',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Goal scope'),
      items: [
        const DropdownMenuItem(value: '', child: Text('Whole library')),
        for (final goal in definitions.values)
          DropdownMenuItem(
            value: goal.id,
            child: Text(goal.displayTitle, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => onChanged(value == '' ? null : value),
    ),
  );
}

class GoalTypeFilter extends StatelessWidget {
  const GoalTypeFilter({super.key, required this.selected, required this.onChanged});

  final GoalType? selected;
  final ValueChanged<GoalType?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - Spacing.xl * 2).clamp(120, 220).toDouble(),
    child: DropdownButtonFormField<GoalType>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Goal type'),
      items: [
        const DropdownMenuItem(child: Text('All types')),
        for (final type in GoalType.values) DropdownMenuItem(value: type, child: Text(type.label)),
      ],
      onChanged: onChanged,
    ),
  );
}

class GoalDateFilter extends StatelessWidget {
  const GoalDateFilter({super.key, required this.dates, required this.onChanged, this.emptyLabel = 'Filter dates'});

  final DateTimeRange? dates;
  final ValueChanged<DateTimeRange?> onChanged;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final range = dates;
    final label = range == null ? emptyLabel : formatDateRangeLabel(range.start, range.end);

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showAppDateRangePicker(
              context: context,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              initialDateRange: range,
            );

            if (picked != null && context.mounted) {
              onChanged(picked);
            }
          },
          icon: const Icon(Icons.date_range_outlined),
          label: Text(label),
        ),
        if (range != null) TextButton(onPressed: () => onChanged(null), child: const Text('Clear dates')),
      ],
    );
  }
}
