// Native notification test host. Uses synthetic data and no user library.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(home: TimerNotificationTestHost()));

class TimerNotificationTestHost extends StatefulWidget {
  const TimerNotificationTestHost({super.key});

  @override
  State<TimerNotificationTestHost> createState() => _TimerNotificationTestHostState();
}

class _TimerNotificationTestHostState extends State<TimerNotificationTestHost> {
  static const channel = MethodChannel('papyrus/reading_timer');
  String result = '';

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async => readActions());
  }

  Future<void> readActions() async {
    final pending = await channel.invokeMethod<Object?>('pending');
    if (mounted) setState(() => result = jsonEncode(pending));
  }

  Future<void> start(bool countdown) async {
    await channel.invokeMethod<void>('clear');
    await channel.invokeMethod<void>('publish', {
      'foreground': true,
      'snapshot': {
        'id': 'notification-native-test',
        'version': 'initial',
        'title': 'A Wizard of Earthsea',
        'phase': 'running',
        'recordedMs': 0,
        'runningSinceMs': DateTime.now().millisecondsSinceEpoch,
        'targetMs': countdown ? 60000 : null,
      },
    });
    await readActions();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Timer notification test')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ElevatedButton(onPressed: () => start(false), child: const Text('Show stopwatch')),
        ElevatedButton(onPressed: () => start(true), child: const Text('Show countdown')),
        ElevatedButton(onPressed: readActions, child: const Text('Read actions')),
        ElevatedButton(onPressed: () => channel.invokeMethod<void>('clear'), child: const Text('Clear')),
        Text(result),
      ],
    ),
  );
}
