import 'dart:io';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/powersync_book_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/goal_period_record.dart';
import 'package:papyrus/powersync/library_database.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:powersync/powersync.dart';
import 'powersync_service_test.dart' show OfflineConnector;

class CapturingUploadRepository implements AuthRepository {
  final batches = <List<Map<String, dynamic>>>[];

  @override
  Future<void> uploadPowerSyncBatch(List<Map<String, dynamic>> batch) async => batches.add(batch);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  final now = DateTime.utc(2026, 10, 6, 12);
  final book = Book(id: 'book', title: 'Book', author: 'Author', addedAt: now, customMetadata: const {'keep': 'value'});

  final activity = ReadingActivity(
    id: 'reading',
    bookId: book.id,
    bookTitle: book.title,
    startTime: now,
    endTime: now.add(const Duration(seconds: 10)),
    createdAt: now.add(const Duration(seconds: 10)),
  );

  final goal = ReadingGoal(
    id: 'goal',
    type: GoalType.minutes,
    targetValue: 30,
    period: GoalPeriod.daily,
    createdAt: now,
    startDate: DateTime.utc(2026, 10, 6),
    endDate: DateTime.utc(2026, 10, 7),
  );

  PapyrusPowerSyncService service() => PapyrusPowerSyncService(
    connectorFactory: OfflineConnector.new,
    connectAuthenticated: false,
    pathResolver: (mode, profile, user) async =>
        '${directory.path}/${mode == LibraryDatabaseMode.guest ? 'guest' : '$profile-$user'}.db',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('papyrus-tracking-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('reconnect refreshes tracking availability after discovery changes', () async {
    var version = 2;
    var failDiscovery = false;

    final db = PapyrusPowerSyncService(
      connectorFactory: OfflineConnector.new,
      connectAuthenticated: false,
      trackingCapability: () async {
        if (failDiscovery) {
          throw StateError('Server unavailable');
        }

        return version;
      },
      pathResolver: (mode, profile, user) async => '${directory.path}/refresh.db',
    );

    addTearDown(db.close);
    await db.activateAuthenticated('one');
    await db.reconnect();
    expect(db.trackingSchemaVersion, 2);
    await db.upsert(book);
    await db.trackingRepository.commitTracking(goals: [goal], activities: [activity]);

    for (final supported in [0, 1, 2]) {
      version = supported;
      await db.reconnect();
      expect(db.trackingSchemaVersion, supported);
      expect(db.supportsTracking, supported == 2);

      final snapshot = await db.watchLibrary().firstWhere(
        (item) => item.activities.isNotEmpty && item.books.isNotEmpty,
      );

      expect(snapshot.activities.single.id, activity.id);
      expect(snapshot.books.single.id, book.id);
    }

    failDiscovery = true;
    await db.reconnect();
    expect(db.trackingSchemaVersion, 0);

    expect(
      (await db.watchLibrary().firstWhere((item) => item.activities.isNotEmpty)).activities.single.id,
      activity.id,
    );
  });

  test('guest restart retains goals and activity after deleting the book', () async {
    final first = service();
    await first.activateGuest();
    await first.upsert(book);
    await first.trackingRepository.commitTracking(goals: [goal], activities: [activity]);
    await first.delete(book.id);
    await first.close();
    final second = service();
    await second.activateGuest();
    final snapshot = await second.watchLibrary().firstWhere((item) => item.activities.isNotEmpty);
    expect(snapshot.goals.single.id, goal.id);
    expect(snapshot.activities.single.id, activity.id);
    expect(snapshot.books, isEmpty);
    await second.close();
  });

  test('old-server tracking stays outside CRUD and promotes atomically on capability upgrade', () async {
    final path = '${directory.path}/account.db';
    final db = PowerSyncDatabase(path: path, schema: papyrusAccountSchema);
    await db.initialize();
    final library = LibraryDatabase(db, () async {});
    await library.commitTracking(goals: [goal], activities: [activity]);
    expect(await db.getAll('SELECT * FROM ps_crud'), isEmpty);
    expect((await library.snapshot()).activities.single.id, activity.id);
    await db.close();
    final reopened = PowerSyncDatabase(path: path, schema: papyrusAccountSchema);
    await reopened.initialize();
    final supported = LibraryDatabase(reopened, () async {});
    expect((await supported.snapshot()).goals.single.id, goal.id);
    await supported.enableTracking();
    expect(await reopened.getAll('SELECT * FROM tracking_staging'), isEmpty);
    expect((await reopened.getAll('SELECT * FROM reading_activities')).length, 1);
    expect((await reopened.getAll('SELECT * FROM ps_crud')).length, 2);
    await supported.commitTracking(activities: [activity]);
    expect((await reopened.getAll('SELECT * FROM ps_crud')).length, 2);
    await reopened.close();
  });

  test('unavailable tracking discovery retains queued tracking while library writes upload', () async {
    final db = PowerSyncDatabase(path: '${directory.path}/downgrade.db', schema: papyrusAccountSchema);
    await db.initialize();
    final library = LibraryDatabase(db, () async {});
    await library.enableTracking();
    await library.commitTracking(goals: [goal], activities: [activity]);
    await library.upsert('books', PowerSyncBookMapper.toRow(book));
    final auth = CapturingUploadRepository();

    final connector = PapyrusPowerSyncConnector(
      authRepository: auth,
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://example.invalid')),
      supportsTracking: () => false,
    );

    await connector.uploadData(db);
    expect(auth.batches.expand((batch) => batch).map((entry) => entry['type']), ['books']);
    expect(await db.getAll('SELECT * FROM ps_crud'), isEmpty);
    expect((await db.getAll('SELECT * FROM tracking_staging')).length, 2);
    await library.enableTracking();
    expect(await db.getAll('SELECT * FROM tracking_staging'), isEmpty);
    expect((await db.getAll('SELECT * FROM ps_crud')).length, 2);
    expect((await library.snapshot()).activities.single.id, activity.id);
    await db.close();
  });

  test('all tracking stays local across restart until current contract is available', () async {
    final path = '${directory.path}/book-sets.db';
    final db = PowerSyncDatabase(path: path, schema: papyrusAccountSchema);
    await db.initialize();
    final library = LibraryDatabase(db, () async {});
    await library.enableTracking(schemaVersion: 0);
    final selected = goal.copyWith(id: 'selected', scope: GoalScope.book, scopeId: 'a', bookIds: ['a', 'b']);

    final period = GoalPeriodRecord(
      id: 'period',
      goalId: selected.id,
      definition: selected.copyWith(isRecurring: false),
    );

    await library.commitTracking(goals: [selected, goal], activities: [activity], periods: [period]);
    expect((await db.getAll('SELECT * FROM tracking_staging')).length, 4);
    expect((await db.getAll('SELECT * FROM ps_crud')).length, 0);
    await db.close();
    final reopened = PowerSyncDatabase(path: path, schema: papyrusAccountSchema);
    await reopened.initialize();
    final supported = LibraryDatabase(reopened, () async {});
    await supported.enableTracking(schemaVersion: 0);
    expect((await supported.snapshot()).goals.firstWhere((goal) => goal.id == 'selected').selectedBookIds, ['a', 'b']);
    expect((await reopened.getAll('SELECT * FROM tracking_staging')).length, 4);
    expect((await supported.snapshot()).goalPeriods.single.definition.selectedBookIds, ['a', 'b']);
    await supported.enableTracking();
    expect(await reopened.getAll('SELECT * FROM tracking_staging'), isEmpty);
    expect((await reopened.getAll('SELECT * FROM ps_crud')).length, 4);
    await supported.enableTracking();
    expect((await reopened.getAll('SELECT * FROM ps_crud')).length, 4);
    await reopened.close();
  });

  test('unsupported tracking contracts defer all tracking uploads', () async {
    final db = PowerSyncDatabase(path: '${directory.path}/book-set-downgrade.db', schema: papyrusAccountSchema);
    await db.initialize();
    final library = LibraryDatabase(db, () async {});
    await library.enableTracking();
    final selected = goal.copyWith(scope: GoalScope.book, scopeId: 'a', bookIds: ['a', 'b']);
    await library.commitTracking(goals: [selected], activities: [activity]);
    await library.upsert('books', PowerSyncBookMapper.toRow(book));
    final auth = CapturingUploadRepository();

    final connector = PapyrusPowerSyncConnector(
      authRepository: auth,
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://example.invalid')),
      trackingSchemaVersion: () => 1,
    );

    await connector.uploadData(db);
    expect(auth.batches.expand((batch) => batch).map((entry) => entry['type']), ['books']);
    expect(await db.getAll('SELECT * FROM ps_crud'), isEmpty);
    expect((await db.getAll('SELECT * FROM tracking_staging')).length, 2);
    await library.enableTracking();
    expect(await db.getAll('SELECT * FROM tracking_staging'), isEmpty);
    expect((await db.getAll('SELECT * FROM ps_crud')).length, 2);
    await db.close();
  });

  test('captured repository is invalidated on account switch and guest data is isolated', () async {
    final db = service();
    await db.activateGuest();
    await db.upsert(book);
    final original = db.trackingRepository;
    await original.commitTracking(goals: [goal], activities: [activity]);
    await db.activateAuthenticated('one');
    expect(original.isCurrent, isFalse);
    await expectLater(original.commitTracking(activities: [activity]), throwsStateError);
    final empty = await db.watchLibrary().firstWhere((item) => item.activities.isEmpty && item.books.isEmpty);
    expect(empty.goals, isEmpty);
    await db.activateGuest();
    final restored = await db.watchLibrary().firstWhere((item) => item.activities.isNotEmpty);
    expect(restored.goals.single.id, goal.id);
    await db.close();
  });

  test('reader patches preserve unrelated edits and commit activity atomically', () async {
    final db = service();
    await db.activateGuest();
    await db.upsert(book);
    await db.upsert(book.copyWith(title: 'Edited title'));

    await db.trackingRepository.commitTracking(
      activities: [activity],
      readerBookId: book.id,
      readerPatch: {
        'current_position': .4,
        'last_read_at': now.toIso8601String(),
        'reader_locator': {'version': 1},
      },
    );

    final updated = (await db.getById(book.id))!;
    expect(updated.title, 'Edited title');
    expect(updated.customMetadata?['keep'], 'value');
    expect(updated.customMetadata?['reader_locator'], {'version': 1});
    expect(updated.currentPosition, .4);

    await db.trackingRepository.commitTracking(readerBookId: book.id, readerPatch: {'current_position': .5});
    expect((await db.getById(book.id))!.customMetadata?['reader_locator'], {'version': 1});

    final invalid = ReadingActivity(
      id: 'rollback',
      bookId: 'gone',
      bookTitle: 'Gone',
      startTime: now,
      endTime: now,
      createdAt: now,
    );

    await db.trackingRepository.commitTracking(
      activities: [invalid],
      readerBookId: 'gone',
      readerPatch: {'current_position': .2},
    );

    expect(await db.getById('gone'), isNull);

    await expectLater(
      db.trackingRepository.commitTracking(
        activities: [activity],
        book: updated.copyWith(title: 'Must roll back'),
        previousBook: updated,
        readerBookId: book.id,
        readerPatch: {'invalid_column': 'invalid'},
      ),
      throwsA(anything),
    );

    expect((await db.getById(book.id))!.title, 'Edited title');
    final snapshot = await db.watchLibrary().firstWhere((item) => item.activities.length == 2);
    expect(snapshot.activities.map((activity) => activity.id).toSet(), {'reading', 'rollback'});
    await db.close();
  });
}
