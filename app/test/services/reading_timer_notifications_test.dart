import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';
import 'package:papyrus/services/reading_timer_notifications.dart';
import 'package:papyrus/timer/reading_timer.dart';

import '../timer/timer_test_library.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/reading_timer_notifications');
  final start = DateTime.utc(2026, 11, 6, 12);
  final book = Book(id: 'book', title: 'A book', author: 'Author', addedAt: start);
  late TimerTestLibrary library;
  late DataStore store;
  late ReadingTimerProvider timer;
  late DateTime now;

  Map<String, dynamic> action(String id, String kind, int seconds) => {
    'id': id,
    'kind': kind,
    'atMs': start.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
  };

  Map<String, dynamic> batch(ReadingTimer original, List<Map<String, dynamic>> actions) => {
    'sessionId': original.id,
    'version': original.version,
    'through': actions.last['id'],
    'actions': actions,
  };

  setUp(() async {
    now = start;
    library = TimerTestLibrary();
    store = DataStore(bookRepository: library);
    timer = ReadingTimerProvider(store, now: () => now, tick: false);
    await pumpEventQueue();
    await timer.start(book);
  });

  tearDown(() async {
    timer.dispose();
    store.dispose();
    await library.trackingRepository.changes.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('background pause and resume use tap timestamps, not app resume time', () async {
    final original = timer.session!;
    now = start.add(const Duration(hours: 2));
    expect(await timer.applyNotificationActions(batch(original, [action('pause', 'pause', 30)])), isTrue);
    expect(timer.elapsed, const Duration(seconds: 30));
    expect(timer.running, isFalse);
    final paused = timer.session!;
    expect(await timer.applyNotificationActions(batch(paused, [action('resume', 'resume', 120)])), isTrue);
    expect(timer.session!.runningSince, start.add(const Duration(seconds: 120)));
  });

  test('queued finish saves only reading intervals once without page input', () async {
    final original = timer.session!;
    final pending = batch(original, [
      action('pause', 'pause', 30),
      action('resume', 'resume', 90),
      action('finish', 'finish', 150),
    ]);
    now = start.add(const Duration(hours: 2));
    expect(await timer.applyNotificationActions(pending), isTrue);
    expect(library.trackingRepository.savedSeconds, 90);
    expect(library.trackingRepository.savedPage, isNull);
    expect(timer.session, isNull);
    expect(await timer.applyNotificationActions(pending), isTrue);
    expect(library.trackingRepository.saves, 1);
  });

  test('replay after a crash skips committed actions and completes finish', () async {
    final original = timer.session!;
    final pending = batch(original, [action('pause', 'pause', 30), action('finish', 'finish', 90)]);
    final persisted = ReadingTimer.fromJson({
      ...original.stop(start.add(const Duration(seconds: 30))).toJson(),
      'version': 'pause',
    });
    await library.trackingRepository.writeTimer(persisted);
    await pumpEventQueue();
    now = start.add(const Duration(hours: 1));
    expect(await timer.applyNotificationActions(pending), isTrue);
    expect(library.trackingRepository.savedSeconds, 30);
    expect(library.trackingRepository.saves, 1);
  });

  test('replay after finish write retries the save without adding time', () async {
    final original = timer.session!;
    final pending = batch(original, [action('finish', 'finish', 30)]);
    final persisted = ReadingTimer.fromJson({
      ...original.stop(start.add(const Duration(seconds: 30)), finish: true).toJson(),
      'version': 'finish',
    });
    await library.trackingRepository.writeTimer(persisted);
    await pumpEventQueue();
    now = start.add(const Duration(hours: 1));
    expect(await timer.applyNotificationActions(pending), isTrue);
    expect(library.trackingRepository.savedSeconds, 30);
  });

  test('stale notification cannot overwrite a remotely changed timer', () async {
    final original = timer.session!;
    final remote = original.stop(start.add(const Duration(seconds: 10)));
    await library.trackingRepository.writeTimer(remote);
    await pumpEventQueue();
    expect(await timer.applyNotificationActions(batch(original, [action('finish', 'finish', 60)])), isTrue);
    expect(timer.session, same(remote));
    expect(library.trackingRepository.saves, 0);
  });

  test('immediate finish discards quietly and countdown is capped at its goal', () async {
    expect(await timer.applyNotificationActions(batch(timer.session!, [action('finish', 'finish', 0)])), isTrue);
    expect(timer.session, isNull);
    expect(library.trackingRepository.saves, 0);
    await timer.start(book, targetSeconds: 60);
    now = start.add(const Duration(minutes: 10));
    expect(await timer.applyNotificationActions(batch(timer.session!, [action('finish2', 'finish', 600)])), isTrue);
    expect(library.trackingRepository.savedSeconds, 60);
  });

  test('native publication uses timestamps and does not update every tick', () async {
    final published = <Map<dynamic, dynamic>>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'publish') published.add(call.arguments as Map);
      return null;
    });
    final notifications = ReadingTimerNotifications(timer, onOpen: () {}, channel: channel, supported: true);
    addTearDown(notifications.dispose);
    await pumpEventQueue();
    expect(published.length, 1);
    expect((published.last['snapshot'] as Map)['runningSinceMs'], start.millisecondsSinceEpoch);
    now = start.add(const Duration(seconds: 15));
    await timer.reload();
    await pumpEventQueue();
    expect(published.length, 1);
    await timer.pause();
    await pumpEventQueue();
    expect((published.last['snapshot'] as Map)['phase'], 'paused');
    expect((published.last['snapshot'] as Map)['recordedMs'], 15000);
  });

  test('failed storage keeps native actions queued until retry succeeds', () async {
    Map<String, dynamic>? pending = batch(timer.session!, [action('pause', 'pause', 30)]);
    var acknowledgements = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pending') return pending;
      if (call.method == 'acknowledge') {
        acknowledgements++;
        pending = null;
      }
      return null;
    });
    library.trackingRepository.failWrite = true;
    final notifications = ReadingTimerNotifications(timer, onOpen: () {}, channel: channel, supported: true);
    addTearDown(notifications.dispose);
    await pumpEventQueue();
    expect(acknowledgements, 0);
    expect(pending, isNotNull);
    library.trackingRepository.failWrite = false;
    now = start.add(const Duration(minutes: 3));
    notifications.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(acknowledgements, 1);
    expect(timer.elapsed, const Duration(seconds: 30));
  });

  test('failed initial loads preserve native actions until the timer is restored', () async {
    final original = timer.session!;
    Map<String, dynamic>? pending = batch(original, [action('pause', 'pause', 30)]);
    var acknowledgements = 0;

    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pending') return pending;

      if (call.method == 'acknowledge') {
        acknowledgements++;
        pending = null;
      }

      return null;
    });

    timer.dispose();
    library.trackingRepository.failLoad = true;
    timer = ReadingTimerProvider(store, now: () => now, tick: false);
    final notifications = ReadingTimerNotifications(timer, onOpen: () {}, channel: channel, supported: true);
    addTearDown(notifications.dispose);
    await pumpEventQueue();
    expect(timer.loading, isFalse);
    expect(timer.error, isNotNull);
    expect(acknowledgements, 0);
    expect(timer.available, isFalse);
    expect(await timer.applyNotificationActions(pending!), isFalse);
    await timer.reload();
    await pumpEventQueue();
    expect(acknowledgements, 0);
    expect(pending, isNotNull);
    library.trackingRepository.failLoad = false;
    now = start.add(const Duration(minutes: 3));
    await timer.reload();
    await pumpEventQueue();
    expect(timer.available, isTrue);
    expect(acknowledgements, 1);
    expect(pending, isNull);
    expect(timer.running, isFalse);
    expect(timer.elapsed, const Duration(seconds: 30));
  });

  test('switching profiles clears native state and rejects old controls', () async {
    final original = timer.session!;
    var clears = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') clears++;
      return null;
    });
    final notifications = ReadingTimerNotifications(timer, onOpen: () {}, channel: channel, supported: true);
    addTearDown(notifications.dispose);
    await pumpEventQueue();
    final next = TimerTestLibrary();
    addTearDown(next.trackingRepository.changes.close);
    next.trackingRepository.timer = ReadingTimer.start(book, start, 'other', []);
    library.trackingRepository.isCurrent = false;
    await store.attachBookRepository(next);
    await pumpEventQueue();
    expect(clears, greaterThan(0));
    expect(await timer.applyNotificationActions(batch(original, [action('finish', 'finish', 50)])), isTrue);
    expect(next.trackingRepository.saves, 0);
  });
}
