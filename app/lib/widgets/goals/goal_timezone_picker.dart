import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:papyrus/goals/goal_calendar.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/goals/goal_controls.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

String timezoneCity(String name) => name.split('/').last.replaceAll('_', ' ');

class GoalTimezonePicker extends StatefulWidget {
  const GoalTimezonePicker({super.key, required this.selected});
  final String selected;
  static Future<String?> show(BuildContext context, {required String selected}) => showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    sheetAnimationStyle: AppMotion.animationStyle(context),
    constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * .85),
    builder: (_) => GoalTimezonePicker(selected: selected),
  );
  @override
  State<GoalTimezonePicker> createState() => _GoalTimezonePickerState();
}

class _GoalTimezonePickerState extends State<GoalTimezonePicker> {
  final _search = TextEditingController();
  late final List<String> _zones;
  @override
  void initState() {
    super.initState();
    GoalCalendar.initialize();
    _zones = {'UTC', ...tz.timeZoneDatabase.locations.keys}.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == widget.selected) return -1;
        if (b == widget.selected) return 1;
        if (a == 'UTC') return -1;
        if (b == 'UTC') return 1;
        return a.compareTo(b);
      });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final zones = _zones.where((name) => name.toLowerCase().replaceAll('_', ' ').contains(query)).toList();
    return GoalControls(
      child: AppBottomSheet(
        title: 'Choose timezone',
        onClose: () => Navigator.pop(context),
        scrollable: false,
        expandBody: true,
        expandOnScroll: false,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Search city or timezone', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: Spacing.md),
            if (zones.isEmpty)
              const Expanded(child: Center(child: Text('No matching timezones.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final name = zones[index];
                    return ListTile(
                      title: Text(timezoneCity(name)),
                      subtitle: Text(name),
                      trailing: name == widget.selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, name),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
