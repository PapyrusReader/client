import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';
import 'package:papyrus/timer/reading_timer.dart';

import '../timer/timer_test_library.dart';

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);
  final book = Book(id: 'physical', title: 'Book', author: 'Author', addedAt: now, isPhysical: true);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('a delayed old-profile load cannot replace the new-profile timer', () async {
    final old = TimerTestLibrary();
    final next = TimerTestLibrary();
    final oldGate = Completer<ReadingTimer?>();
    old.trackingRepository.loadGate = oldGate;
    next.trackingRepository.timer = ReadingTimer.start(book, now, 'next', []);
    final store = DataStore(bookRepository: old);
    final timer = ReadingTimerProvider(store, now: () => now, tick: false);
    addTearDown(timer.dispose);
    addTearDown(store.dispose);
    await flush();
    old.trackingRepository.isCurrent = false;
    await store.attachBookRepository(next);
    await flush();
    oldGate.complete(ReadingTimer.start(book, now, 'old', []));
    await flush();
    expect(timer.session!.deviceId, 'next');
    expect(timer.loading, isFalse);
  });

  test('switch during a pending start never copies the old draft into the new library', () async {
    final old = TimerTestLibrary();
    final next = TimerTestLibrary();
    final store = DataStore(bookRepository: old);
    final timer = ReadingTimerProvider(store, now: () => now, tick: false);
    addTearDown(timer.dispose);
    addTearDown(store.dispose);
    await flush();
    final gate = Completer<void>();
    old.trackingRepository.writeGate = gate;
    final starting = timer.start(book);
    old.trackingRepository.isCurrent = false;
    await store.attachBookRepository(next);
    await flush();
    gate.complete();
    expect(await starting, isFalse);
    await flush();
    expect(timer.session, isNull);
    expect(next.trackingRepository.timer, isNull);
    expect(timer.busy, isFalse);
    expect(timer.error, isNull);
  });

  test('a second start while persistence is pending cannot create another timer', () async {
    final library = TimerTestLibrary();
    final store = DataStore(bookRepository: library);
    final timer = ReadingTimerProvider(store, now: () => now, tick: false);
    addTearDown(timer.dispose);
    addTearDown(store.dispose);
    await flush();
    final gate = Completer<void>();
    library.trackingRepository.writeGate = gate;
    final starting = timer.start(book);
    expect(await timer.start(book), isFalse);
    gate.complete();
    expect(await starting, isTrue);
    expect(timer.session, isNotNull);
  });

  test('remote transitions update the same clock without resetting elapsed time', () async {
    final library = TimerTestLibrary();
    final store = DataStore(bookRepository: library);
    var clock = now.add(const Duration(minutes: 2));
    final timer = ReadingTimerProvider(store, now: () => clock, tick: false);
    addTearDown(timer.dispose);
    addTearDown(store.dispose);
    await flush();
    final remote = ReadingTimer.start(book, now, 'browser', [], targetSeconds: 300);
    await library.trackingRepository.writeTimer(remote);
    await flush();
    expect(timer.session!.id, remote.id);
    expect(timer.elapsed, const Duration(minutes: 2));
    expect(timer.running, isTrue);
    final paused = remote.stop(clock);
    await library.trackingRepository.writeTimer(paused, previous: remote);
    clock = clock.add(const Duration(minutes: 4));
    await flush();
    expect(timer.running, isFalse);
    expect(timer.elapsed, const Duration(minutes: 2));
    final resumed = paused.resume(clock);
    await library.trackingRepository.writeTimer(resumed, previous: paused);
    clock = clock.add(const Duration(minutes: 10));
    await flush();
    expect(timer.goalReached, isTrue);
    expect(timer.elapsed, const Duration(minutes: 5));
    await library.trackingRepository.finishTimer(resumed, clock);
    await flush();
    expect(timer.session, isNull);
  });

  test('deleting the local draft externally clears the displayed session', () async {
    final library = TimerTestLibrary();
    final store = DataStore(bookRepository: library);
    final timer = ReadingTimerProvider(store, now: () => now, tick: false);
    addTearDown(timer.dispose);
    addTearDown(store.dispose);
    await flush();
    await timer.start(book);
    await flush();
    await library.trackingRepository.discardTimer(timer.session!);
    await flush();
    expect(timer.session, isNull);
  });
}
