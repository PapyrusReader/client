import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyrus/widgets/goals/goal_card.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/goals/goal_timezone_picker.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';

class AddGoalSheet extends StatefulWidget {
  const AddGoalSheet({super.key, required this.provider, this.editing, this.preset, this.initialTimezone});
  final GoalsProvider provider;
  final ReadingGoal? editing;
  final int? preset;
  final String? initialTimezone;
  static Future<void> show(
    BuildContext context, {
    required GoalsProvider provider,
    ReadingGoal? editing,
    int? preset,
    String? initialTimezone,
  }) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) =>
        AddGoalSheet(provider: provider, editing: editing, preset: preset, initialTimezone: initialTimezone),
  );
  @override
  State<AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<AddGoalSheet> {
  final _form = GlobalKey<FormState>();
  final _target = TextEditingController();
  final _title = TextEditingController();
  final _threshold = TextEditingController(text: '5');
  final _zone = TextEditingController(text: 'UTC');
  late final TrackingRepository? _repository;
  GoalType _type = GoalType.minutes;
  GoalPeriod _period = GoalPeriod.daily;
  GoalScope _scope = GoalScope.library;
  String? _scopeId;
  bool _recurring = true;
  bool _choosingMetric = false;
  bool _saving = false;
  bool _timezoneReady = false;
  String? _error;
  DateTime _deadline = DateTime.now().add(const Duration(days: 30));
  @override
  void initState() {
    super.initState();
    _repository = widget.provider.store.trackingRepository;
    _choosingMetric = widget.editing == null && widget.preset == null;
    _applyPreset(widget.preset ?? 0);
    final editing = widget.editing;
    if (editing != null) {
      _type = editing.type;
      _period = editing.period;
      _scope = editing.scope;
      _scopeId = editing.scopeId;
      _recurring = editing.isRecurring;
      _target.text = '${editing.targetValue}';
      _title.text = editing.title ?? '';
      _threshold.text = '${editing.minimumMinutes}';
      _zone.text = editing.timezone;
      _deadline = GoalCalendar.local(editing.endDate.subtract(const Duration(microseconds: 1)), editing.timezone);
      _timezoneReady = true;
    } else if (widget.initialTimezone != null) {
      _zone.text = widget.initialTimezone!;
      _timezoneReady = true;
    } else {
      GoalCalendar.deviceTimezone()
          .then((zone) {
            if (mounted) {
              setState(() {
                _zone.text = zone;
                _timezoneReady = true;
              });
            }
          })
          .catchError((Object error) {
            if (mounted) {
              setState(() {
                _timezoneReady = true;
                _error =
                    'Could not detect your timezone. Using UTC; choose another timezone in advanced settings if needed.';
              });
            }
          });
    }
  }

  void _applyPreset(int index) {
    _type = [GoalType.minutes, GoalType.days, GoalType.books, GoalType.pages, GoalType.books][index];
    _period = [GoalPeriod.daily, GoalPeriod.weekly, GoalPeriod.yearly, GoalPeriod.weekly, GoalPeriod.custom][index];
    _target.text = ['30', '5', '12', '100', '1'][index];
    _scope = index == 4 ? GoalScope.book : GoalScope.library;
    _scopeId = null;
    _recurring = index != 4;
  }

  @override
  void dispose() {
    _target.dispose();
    _title.dispose();
    _threshold.dispose();
    _zone.dispose();
    super.dispose();
  }

  String? _positive(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 1 || number > 100000 ? 'Enter a number from 1 to 100,000.' : null;
  }

  String _metricLabel(GoalType type) => switch (type) {
    GoalType.books => 'Books finished',
    GoalType.pages => 'Pages read',
    GoalType.minutes => 'Reading time',
    GoalType.days => 'Reading days',
  };

  void _chooseMetric(GoalType type) => setState(() {
    _applyPreset({GoalType.books: 2, GoalType.pages: 3, GoalType.minutes: 0, GoalType.days: 1}[type]!);
    _choosingMetric = false;
  });

  void _adjustTarget(int delta) => setState(() {
    final value = ((int.tryParse(_target.text) ?? 0) + delta).clamp(1, 100000);
    _target.text = '$value';
    _target.selection = TextSelection.collapsed(offset: _target.text.length);
  });

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    final texts = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    if (_choosingMetric) {
      return GoalControls(
        child: AppBottomSheet(
          title: 'New goal',
          onClose: () => Navigator.pop(context),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What would you like to track?', style: texts.titleLarge),
              const SizedBox(height: Spacing.lg),
              for (final type in GoalType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Material(
                    color: colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                      leading: Icon(goalIcon(type), color: colors.primary),
                      title: Text(_metricLabel(type)),
                      subtitle: Text(switch (type) {
                        GoalType.books => 'Finish books from your library',
                        GoalType.pages => 'Read a set number of pages',
                        GoalType.minutes => 'Make time for reading',
                        GoalType.days => 'Read regularly throughout the week',
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _chooseMetric(type),
                    ),
                  ),
                ),
            ],
          ),
          footer: BottomSheetActions(
            primary: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
        ),
      );
    }
    final store = widget.provider.store;
    final preview = ReadingGoal(
      id: 'preview',
      title: _title.text.isEmpty ? null : _title.text,
      type: _type,
      targetValue: int.tryParse(_target.text) ?? 0,
      period: _period,
      startDate: DateTime.now(),
      endDate: _deadline,
      isRecurring: _recurring,
    );
    final items = _scope == GoalScope.book
        ? {for (final book in store.books) book.id: book.title}
        : {for (final shelf in store.shelves) shelf.id: shelf.name};
    return GoalControls(
      child: AppBottomSheet(
        title: editing ? 'Edit goal' : 'New goal',
        canClose: !_saving,
        onClose: () => Navigator.pop(context),
        body: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<GoalType>(
                initialValue: _type,
                key: ValueKey('metric-$_type'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Measure'),
                items: [
                  for (final type in GoalType.values) DropdownMenuItem(value: type, child: Text(_metricLabel(type))),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _type = value!;
                      }),
              ),
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Row(
                    children: [
                      IconButton.outlined(
                        tooltip: 'Decrease target',
                        onPressed: _saving ? null : () => _adjustTarget(-1),
                        icon: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: TextFormField(
                          key: const Key('goal-target-input'),
                          controller: _target,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.center,
                          style: texts.headlineSmall,
                          decoration: const InputDecoration(labelText: 'Target'),
                          validator: _positive,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      IconButton.outlined(
                        tooltip: 'Increase target',
                        onPressed: _saving ? null : () => _adjustTarget(1),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(preview.typeLabel, style: texts.bodyMedium),
              const SizedBox(height: Spacing.lg),
              Text('Schedule', style: texts.titleSmall),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final period in GoalPeriod.values)
                    ChoiceChip(
                      label: Text(switch (period) {
                        GoalPeriod.daily => 'Daily',
                        GoalPeriod.weekly => 'Weekly',
                        GoalPeriod.monthly => 'Monthly',
                        GoalPeriod.yearly => 'Yearly',
                        GoalPeriod.custom => 'By date',
                      }),
                      selected: _period == period,
                      showCheckmark: false,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _period = period;
                              if (period == GoalPeriod.custom) _recurring = false;
                            }),
                    ),
                ],
              ),
              if (_period == GoalPeriod.custom)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final date = await showAppDatePicker(
                                context: context,
                                initialDate: _deadline.isBefore(DateTime.now()) ? DateTime.now() : _deadline,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 3650)),
                              );
                              if (date != null && mounted) setState(() => _deadline = date);
                            },
                      icon: const Icon(Icons.event_outlined),
                      label: Text('Deadline: ${_deadline.day}/${_deadline.month}/${_deadline.year}'),
                    ),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _title,
                enabled: !_saving,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Name (optional)', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
              if (_scope == GoalScope.book) ...[const SizedBox(height: Spacing.md), _scopeItem(items)],
              const SizedBox(height: Spacing.sm),
              ExpansionTile(
                key: const Key('goal-advanced-settings'),
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced settings'),
                children: [
                  DropdownButtonFormField<GoalScope>(
                    initialValue: _scope,
                    key: ValueKey('scope-$_scope'),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Include'),
                    items: [
                      for (final scope in GoalScope.values)
                        DropdownMenuItem(
                          value: scope,
                          child: Text(switch (scope) {
                            GoalScope.library => 'Whole library',
                            GoalScope.book => 'A book',
                            GoalScope.shelf => 'A shelf',
                          }),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _scope = value!;
                            _scopeId = null;
                          }),
                  ),
                  if (_scope == GoalScope.shelf) ...[const SizedBox(height: Spacing.md), _scopeItem(items)],
                  if (_period != GoalPeriod.custom)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Repeat each period'),
                      value: _recurring,
                      onChanged: _saving ? null : (value) => setState(() => _recurring = value),
                    ),
                  if (_type == GoalType.days)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      child: _compact(
                        width: 320,
                        child: TextFormField(
                          controller: _threshold,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minutes to qualify a day',
                            helperText: 'Time adds up throughout the day.',
                          ),
                          validator: (value) {
                            final n = int.tryParse(value ?? '');
                            return n == null || n < 1 || n > 1440 ? 'Enter 1–1,440 minutes.' : null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  const SizedBox(height: Spacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const Key('goal-timezone-button'),
                      onPressed: _saving
                          ? null
                          : () async {
                              final zone = await GoalTimezonePicker.show(context, selected: _zone.text);
                              if (zone != null && mounted) setState(() => _zone.text = zone);
                            },
                      icon: const Icon(Icons.public_outlined),
                      label: Text('Timezone: ${timezoneCity(_zone.text)}'),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  const Text('Defaults to your device. Calendar periods use this timezone across your devices.'),
                  const SizedBox(height: Spacing.md),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(
                '${preview.description}. ${_scope == GoalScope.library ? 'Across your library' : items[_scopeId] ?? 'Choose a book or shelf'}.',
                style: texts.bodyLarge,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                editing
                    ? (_replacementNeeded
                          ? 'This starts a replacement goal and preserves the original history. Only new reading counts.'
                          : 'Past periods keep their original target.')
                    : 'Progress updates from reading and manual logs after you create the goal.',
                style: texts.bodySmall,
              ),
              if (_type == GoalType.days)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text('${_threshold.text} minutes qualifies a reading day.', style: texts.bodySmall),
                ),
              if (_type == GoalType.pages)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    'PDF pages are measured. EPUB pages are estimated when page metadata is available.',
                    style: texts.bodySmall,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
            ],
          ),
        ),
        footer: BottomSheetFormActions(
          onCancel: _saving ? null : () => Navigator.pop(context),
          onSave: _saving || !_timezoneReady ? null : _save,
          saveLabel: _saving
              ? 'Saving…'
              : editing
              ? (_replacementNeeded ? 'Replace goal' : 'Save')
              : 'Create goal',
        ),
      ),
    );
  }

  Widget _scopeItem(Map<String, String> items) => DropdownButtonFormField<String>(
    initialValue: items.containsKey(_scopeId) ? _scopeId : null,
    key: ValueKey('scope-item-$_scope-$_scopeId'),
    isExpanded: true,
    decoration: InputDecoration(labelText: _scope == GoalScope.book ? 'Book' : 'Shelf'),
    items: [
      for (final item in items.entries)
        DropdownMenuItem(
          value: item.key,
          child: Text(item.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    validator: (value) => value == null ? 'Choose ${_scope == GoalScope.book ? 'a book' : 'a shelf'}.' : null,
    onChanged: _saving ? null : (value) => setState(() => _scopeId = value),
  );

  Widget _compact({required Widget child, double width = 220}) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );

  bool get _replacementNeeded {
    final goal = widget.editing;
    if (goal == null) return false;
    final zone = _zone.text.trim();
    final originalDeadline = GoalCalendar.local(goal.endDate.subtract(const Duration(microseconds: 1)), goal.timezone);
    final deadlineChanged =
        _period == GoalPeriod.custom &&
        (_deadline.year != originalDeadline.year ||
            _deadline.month != originalDeadline.month ||
            _deadline.day != originalDeadline.day);
    return _type != goal.type ||
        _period != goal.period ||
        _scope != goal.scope ||
        _scopeId != goal.scopeId ||
        _recurring != goal.isRecurring ||
        zone != goal.timezone ||
        int.tryParse(_threshold.text) != goal.minimumMinutes ||
        deadlineChanged;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.editing != null && !_replacementNeeded) {
        await widget.provider.updateGoal(
          goalId: widget.editing!.id,
          target: int.parse(_target.text),
          title: _title.text.trim(),
          repository: _repository,
        );
      } else {
        await widget.provider.createGoal(
          replaceGoalId: widget.editing?.id,
          type: _type,
          target: int.parse(_target.text),
          period: _period,
          isRecurring: _recurring,
          title: _title.text.trim(),
          scope: _scope,
          scopeId: _scopeId,
          minimumMinutes: int.parse(_threshold.text),
          timezone: _zone.text.trim(),
          endDate: _period == GoalPeriod.custom ? GoalCalendar.deadline(_deadline, _zone.text.trim()) : null,
          repository: _repository,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}
