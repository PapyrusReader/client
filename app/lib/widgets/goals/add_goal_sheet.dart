import 'package:flutter/material.dart';
import 'package:papyrus/data/repositories/tracking_repository.dart';
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/providers/goals_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_date_picker.dart';

class AddGoalSheet extends StatefulWidget {
  const AddGoalSheet({super.key, required this.provider, this.editing, this.preset = 0, this.initialTimezone});
  final GoalsProvider provider;
  final ReadingGoal? editing;
  final int preset;
  final String? initialTimezone;
  static Future<void> show(
    BuildContext context, {
    required GoalsProvider provider,
    ReadingGoal? editing,
    int preset = 0,
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
  bool _saving = false;
  bool _timezoneReady = false;
  String? _error;
  int _preset = 0;
  DateTime _deadline = DateTime.now().add(const Duration(days: 30));
  @override
  void initState() {
    super.initState();
    _repository = widget.provider.store.trackingRepository;
    _applyPreset(widget.preset);
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
                _error = 'Could not detect your timezone. Check the timezone below before saving.';
              });
            }
          });
    }
  }

  void _applyPreset(int index) {
    _preset = index;
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
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
    return AppBottomSheet(
      title: editing ? 'Edit goal' : 'New goal',
      canClose: !_saving,
      onClose: () => Navigator.pop(context),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!editing) ...[
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (var i = 0; i < 5; i++)
                    ChoiceChip(
                      label: Text(
                        ['Daily time', 'Reading days', 'Books this year', 'Weekly pages', 'Finish a book'][i],
                      ),
                      selected: _preset == i,
                      onSelected: _saving ? null : (_) => setState(() => _applyPreset(i)),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
            ],
            TextFormField(
              controller: _title,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<GoalType>(
              initialValue: _type,
              key: ValueKey('metric-$_type'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Measure'),
              items: [
                for (final type in GoalType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(
                      {
                        GoalType.books: 'Books finished',
                        GoalType.pages: 'Pages read',
                        GoalType.minutes: 'Reading time (minutes)',
                        GoalType.days: 'Reading days',
                      }[type]!,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _type = value!;
                      _preset = -1;
                    }),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Target (${preview.typeLabel})'),
              validator: _positive,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<GoalPeriod>(
              initialValue: _period,
              key: ValueKey('period-$_period'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Schedule'),
              items: [
                for (final period in GoalPeriod.values)
                  DropdownMenuItem(
                    value: period,
                    child: Text(
                      {
                        GoalPeriod.daily: 'Daily',
                        GoalPeriod.weekly: 'Weekly',
                        GoalPeriod.monthly: 'Monthly',
                        GoalPeriod.yearly: 'Yearly',
                        GoalPeriod.custom: 'By a deadline',
                      }[period]!,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _period = value!;
                      if (_period == GoalPeriod.custom) _recurring = false;
                    }),
            ),
            if (_period == GoalPeriod.custom)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
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
              )
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat each period'),
                value: _recurring,
                onChanged: _saving ? null : (value) => setState(() => _recurring = value),
              ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<GoalScope>(
              initialValue: _scope,
              key: ValueKey('scope-$_scope'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Include'),
              items: [
                for (final scope in GoalScope.values)
                  DropdownMenuItem(
                    value: scope,
                    child: Text(
                      {
                        GoalScope.library: 'Whole library',
                        GoalScope.book: 'A book',
                        GoalScope.shelf: 'A shelf',
                      }[scope]!,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _scope = value!;
                      _scopeId = null;
                    }),
            ),
            if (_scope != GoalScope.library) ...[
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
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
                validator: (value) =>
                    value == null ? 'Choose ${_scope == GoalScope.book ? 'a book' : 'a shelf'}.' : null,
                onChanged: _saving ? null : (value) => setState(() => _scopeId = value),
              ),
            ],
            if (_type == GoalType.days) ...[
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _threshold,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minimum minutes per reading day',
                  helperText: 'Time adds up throughout the day.',
                ),
                validator: (value) {
                  final n = int.tryParse(value ?? '');
                  return n == null || n < 1 || n > 1440 ? 'Enter 1–1,440 minutes.' : null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _zone,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                helperText: 'Calendar periods follow this timezone on every device.',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                try {
                  GoalCalendar.location(value ?? '');
                  return null;
                } catch (_) {
                  return 'Use an IANA timezone, such as Europe/Vilnius.';
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Text(
              '${preview.description}. ${_scope == GoalScope.library ? 'Across your library' : items[_scopeId] ?? 'Choose a book or shelf'}.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              editing
                  ? (_replacementNeeded
                        ? 'This change starts a replacement goal. The current goal is archived with its history; only new reading counts toward the replacement.'
                        : 'Past periods keep their original target.')
                  : 'Only reading after this goal is created counts. Progress comes from the reader and your manual logs.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_type == GoalType.pages)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.sm),
                child: Text('PDF pages are measured. EPUB pages are estimated when page-count metadata is available.'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    );
  }

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
