import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/powersync/library_database.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'tracking_persistence_test.dart' show CapturingUploadRepository;
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/timer/reading_timer.dart';
import 'package:powersync/powersync.dart';

void main() {
  final start = DateTime.utc(2026, 11, 3, 23, 50);
  final book = Book(
    id: 'physical',
    title: 'Physical book',
    author: 'Author',
    addedAt: start,
    isPhysical: true,
    currentPage: 10,
    pageCount: 100,
  );

  late Directory directory;
  late PowerSyncDatabase database;
  late LibraryDatabase library;

  Future<void> open({bool account = false}) async {
    database = PowerSyncDatabase(
      path: '${directory.path}/timer.db',
      schema: account ? papyrusAccountSchema : papyrusGuestSchema,
    );
    await database.initialize();
    library = LibraryDatabase(database, () async {})..trackingSupported = !account;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('papyrus-timer-');
    await open();
    await library.books.upsert(book);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('running timer survives closing SQLite and caps a suspended countdown', () async {
    final timer = ReadingTimer.start(book, start, 'device', [], targetSeconds: 1200);
    await library.writeTimer(timer);
    await database.close();
    await open();
    final restored = (await library.loadTimer())!;
    final later = start.add(const Duration(hours: 3));
    expect(restored.elapsed(later), const Duration(minutes: 20));
    expect(restored.isRunning(later), isFalse);
    await library.finishTimer(restored, later, currentPage: 25);
    expect(await library.loadTimer(), isNull);
    final snapshot = await library.snapshot();
    expect(snapshot.activities.single.seconds, 1200);
    expect(snapshot.activities.single.pages, 15);
    expect(snapshot.activities.single.endTime, start.add(const Duration(minutes: 20)));
    expect(snapshot.books.single.currentPage, 25);
    expect(snapshot.books.single.readingStatus, LibraryReadingStatus.inProgress);
    await expectLater(library.finishTimer(restored, later, currentPage: 25), throwsStateError);
    expect((await library.snapshot()).activities.length, 1);
  });

  test('pauses preserve real intervals across midnight and group into one session', () async {
    var timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    var next = timer.stop(start.add(const Duration(minutes: 5)));
    await library.writeTimer(next, previous: timer);
    timer = next;
    next = timer.resume(start.add(const Duration(minutes: 20)));
    await library.writeTimer(next, previous: timer);
    timer = next;
    final end = start.add(const Duration(minutes: 30));
    await library.finishTimer(timer, end, currentPage: 30);
    final activities = (await library.snapshot()).activities;
    expect(activities.map((activity) => activity.seconds).reduce((left, right) => left + right), 900);
    final grouped = groupReadingActivities(activities);
    expect(grouped.length, 1);
    expect(grouped.single.seconds, 900);
    expect(grouped.single.pages, 20);
    expect(grouped.single.constituentIds.length, 2);
    expect(activities.map((activity) => activity.startTime), contains(start.add(const Duration(minutes: 20))));
  });

  test('digital book sessions persist without changing the saved reader position', () async {
    final digital = Book(
      id: 'digital',
      title: 'Ebook',
      author: 'Author',
      addedAt: start,
      currentPage: 12,
      currentPosition: 0.3,
      currentCfi: 'saved-reader-position',
    );

    await library.books.upsert(digital);
    final timer = ReadingTimer.start(digital, start, 'device', [], targetSeconds: 300);
    await library.writeTimer(timer);
    await library.finishTimer(timer, start.add(const Duration(minutes: 10)));
    final snapshot = await library.snapshot();
    final saved = snapshot.books.singleWhere((book) => book.id == digital.id);
    expect(snapshot.activities.single.bookId, digital.id);
    expect(snapshot.activities.single.seconds, 300);
    expect(saved.currentPage, 12);
    expect(saved.currentPosition, 0.3);
    expect(saved.currentCfi, digital.currentCfi);
    expect(await library.loadTimer(), isNull);
  });

  test('subsecond pauses retain the same saved total as the timer display', () async {
    var timer = ReadingTimer.start(book, start, 'device', []);
    timer = timer.stop(start.add(const Duration(milliseconds: 900)));
    timer = timer.resume(start.add(const Duration(seconds: 2)));
    final end = start.add(const Duration(milliseconds: 2900));
    await library.writeTimer(timer);
    await library.finishTimer(timer, end);
    final saved = groupReadingActivities((await library.snapshot()).activities).single;
    expect(timer.elapsed(end).inSeconds, 1);
    expect(saved.seconds, timer.elapsed(end).inSeconds);
  });

  test('negative page input rolls back and retains the draft for retry', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    final end = start.add(const Duration(minutes: 10));
    await expectLater(library.finishTimer(timer, end, currentPage: -1), throwsArgumentError);
    expect((await library.loadTimer())!.id, timer.id);
    expect((await library.snapshot()).activities, isEmpty);
    await library.finishTimer(timer, end, currentPage: 100);
    final snapshot = await library.snapshot();
    expect(snapshot.books.single.readingStatus, LibraryReadingStatus.completed);
    expect(snapshot.activities.where((activity) => activity.kind == 'completion').length, 1);
  });

  for (final (page, pagesRead, position) in [(199, 189, 1.0), (5, 0, 0.05)]) {
    test('saves page $page outside the prior page range', () async {
      final timer = ReadingTimer.start(book, start, 'device', []);
      await library.writeTimer(timer);
      await library.finishTimer(timer, start.add(const Duration(minutes: 2)), currentPage: page);
      final snapshot = await library.snapshot();
      expect(snapshot.books.single.currentPage, page);
      expect(snapshot.books.single.pageCount, 100);
      expect(snapshot.books.single.currentPosition, position);
      expect(snapshot.activities.single.pages, pagesRead);
      expect(snapshot.activities.single.seconds, 120);
      expect(await library.loadTimer(), isNull);
    });
  }

  test('stale windows cannot overwrite, discard or save a newer timer', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    final paused = timer.stop(start.add(const Duration(minutes: 2)));
    await library.writeTimer(paused, previous: timer);
    await expectLater(library.writeTimer(timer.stop(start), previous: timer), throwsStateError);
    await expectLater(library.discardTimer(timer), throwsStateError);
    await expectLater(library.finishTimer(timer, start.add(const Duration(minutes: 3))), throwsStateError);
    expect((await library.loadTimer())!.revision, paused.revision);
  });

  test('same-numbered revisions from different device branches are not interchangeable', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    final accepted = timer.stop(start.add(const Duration(minutes: 1)));
    final stale = timer.stop(start.add(const Duration(minutes: 2)));
    expect(accepted.revision, stale.revision);
    expect(accepted.version, isNot(stale.version));
    await library.writeTimer(accepted, previous: timer);
    await expectLater(library.discardTimer(stale), throwsStateError);
    await expectLater(library.finishTimer(stale, start.add(const Duration(minutes: 3))), throwsStateError);
    expect((await library.loadTimer())!.version, accepted.version);
  });

  test('invalidated profile handle cannot read or mutate its timer', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    library.active = false;
    await expectLater(library.loadTimer(), throwsStateError);
    await expectLater(library.discardTimer(timer), throwsStateError);
    await expectLater(library.finishTimer(timer, start.add(const Duration(minutes: 5))), throwsStateError);
    library.active = true;
    expect((await library.loadTimer())!.id, timer.id);
  });

  test('account timer transitions and saved history enter one upload transaction', () async {
    await database.close();
    await open(account: true);
    await library.books.upsert(book);
    await database.execute('DELETE FROM ps_crud');
    final timer = ReadingTimer.start(book, start, 'device', [], targetSeconds: 60);
    await library.writeTimer(timer);
    final startTransaction = (await database.getNextCrudTransaction())!;
    expect(startTransaction.crud.single.table, 'reading_timers');
    expect(startTransaction.crud.single.id, timer.id);
    expect(startTransaction.crud.single.opData!['status'], 'active');
    await startTransaction.complete();
    await library.finishTimer(timer, start.add(const Duration(minutes: 3)));
    expect(await library.loadTimer(), isNull);
    expect((await library.snapshot()).activities.single.seconds, 60);
    expect(await database.getAll('SELECT * FROM tracking_staging'), isEmpty);
    final finishTransaction = (await database.getNextCrudTransaction())!;
    expect(finishTransaction.crud.map((entry) => entry.table), ['reading_timers', 'reading_activities', 'books']);
    expect(finishTransaction.crud.first.opData!['status'], 'saved');
    expect(finishTransaction.crud.first.opData!['base_version'], timer.version);
    expect(await database.getNextCrudTransaction(), isNotNull);
  });

  test('capability discovery cannot split a timer save from its history upload', () async {
    await database.close();
    await open(account: true);
    await library.books.upsert(book);
    await database.execute('DELETE FROM ps_crud');
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    await library.finishTimer(timer, start.add(const Duration(minutes: 2)));
    final auth = CapturingUploadRepository();

    final connector = PapyrusPowerSyncConnector(
      authRepository: auth,
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://example.invalid')),
      supportsTracking: () => false,
    );

    await connector.uploadData(database);
    expect(auth.batches, hasLength(2));
    expect(auth.batches.last.map((entry) => entry['type']), ['reading_timers', 'reading_activities', 'books']);
    expect((auth.batches.last.first['data'] as Map)['base_version'], timer.version);
    expect((auth.batches.last.first['data'] as Map)['payload'], isA<Map>());
    expect(await database.getAll('SELECT * FROM tracking_staging'), isEmpty);
    expect(await database.getAll('SELECT * FROM ps_crud'), isEmpty);
  });

  test('existing local timers migrate once without losing elapsed time', () async {
    final timer = ReadingTimer.start(book, start, 'device', []).stop(start.add(const Duration(minutes: 3)));
    final payload = timer.toJson()..remove('version');
    await database.execute('INSERT INTO reading_timer (id, payload) VALUES (?, ?)', ['active', jsonEncode(payload)]);
    await library.migrateTimer();
    await library.migrateTimer();
    final restored = (await library.loadTimer())!;
    expect(restored.id, timer.id);
    expect(restored.elapsed(start.add(const Duration(hours: 1))), const Duration(minutes: 3));
    expect(await database.getAll('SELECT * FROM reading_timer'), isEmpty);
    expect(await database.getAll('SELECT * FROM reading_timers'), hasLength(1));
    expect(await database.getAll('SELECT * FROM ps_crud'), isEmpty);
  });

  test('a terminal record disappears from watches and stays durable after reopening', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    final closed = library.watchTimer().firstWhere((value) => value == null);
    await library.discardTimer(timer);
    await closed.timeout(const Duration(seconds: 2));
    await database.close();
    await open();
    expect(await library.loadTimer(), isNull);
    expect((await database.get('SELECT status FROM reading_timers WHERE id = ?', [timer.id]))['status'], 'discarded');
  });

  test('deleted book leaves the timer recoverable without resurrecting the book', () async {
    final timer = ReadingTimer.start(book, start, 'device', []);
    await library.writeTimer(timer);
    await library.books.delete(book.id);
    await expectLater(library.finishTimer(timer, start.add(const Duration(minutes: 2))), throwsStateError);
    expect((await library.loadTimer())!.id, timer.id);
    expect((await library.snapshot()).books, isEmpty);
    await library.discardTimer(timer);
    expect(await library.loadTimer(), isNull);
  });
}
