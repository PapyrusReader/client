import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/sample_data.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:papyrus/powersync/powersync_book_mapper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

class PapyrusPowerSyncService implements BookSyncWriter {
  final AuthRepository authRepository;
  final PapyrusApiConfig config;
  final DataStore dataStore;

  PowerSyncDatabase? _database;
  StreamSubscription? _booksSubscription;
  Future<void>? _connectOperation;
  bool _isConnected = false;

  PapyrusPowerSyncService({required this.authRepository, required this.config, required this.dataStore});

  Future<void> connect() {
    if (_isConnected) {
      return Future.value();
    }

    _connectOperation ??= _connect().whenComplete(() {
      _connectOperation = null;
    });

    return _connectOperation!;
  }

  Future<void> showOfflineSampleData() async {
    await disconnectAndClear();
    dataStore.loadData(
      books: SampleData.books,
      shelves: SampleData.shelves,
      tags: SampleData.tags,
      series: SampleData.seriesList,
      annotations: SampleData.annotations,
      notes: SampleData.notes,
      bookmarks: SampleData.bookmarks,
      readingSessions: SampleData.readingSessions,
      readingGoals: SampleData.readingGoals,
      bookShelfRelations: SampleData.bookShelfRelations,
      bookTagRelations: SampleData.bookTagRelations,
    );
  }

  Future<void> disconnectAndClear() async {
    _isConnected = false;
    dataStore.attachBookSyncWriter(null);
    await _booksSubscription?.cancel();
    _booksSubscription = null;

    final database = _database;

    if (database != null) {
      await database.disconnectAndClear();
    }

    dataStore.clear();
  }

  Future<void> close() async {
    _isConnected = false;
    dataStore.attachBookSyncWriter(null);
    await _booksSubscription?.cancel();
    await _database?.close();
  }

  @override
  Future<void> upsertBook(Book book) async {
    final database = await _openDatabase();
    final row = PowerSyncBookMapper.toRow(book);
    final existing = await database.getOptional('SELECT id FROM books WHERE id = ?', [book.id]);

    if (existing == null) {
      await database.execute(PowerSyncBookMapper.insertSql(), PowerSyncBookMapper.rowParameters(row));
      return;
    }

    await database.execute(PowerSyncBookMapper.updateSql(), PowerSyncBookMapper.updateParameters(row));
  }

  @override
  Future<void> deleteBook(String id) async {
    final database = await _openDatabase();
    await database.execute('DELETE FROM books WHERE id = ?', [id]);
  }

  Future<void> _connect() async {
    final database = await _openDatabase();
    dataStore.clear();
    dataStore.attachBookSyncWriter(this);
    _watchBooks(database);

    await database.connect(
      connector: PapyrusPowerSyncConnector(authRepository: authRepository, config: config),
    );
    _isConnected = true;
  }

  Future<PowerSyncDatabase> _openDatabase() async {
    final existing = _database;

    if (existing != null) {
      return existing;
    }

    final database = PowerSyncDatabase(schema: papyrusPowerSyncSchema, path: await _databasePath());
    await database.initialize();
    _database = database;
    return database;
  }

  Future<String> _databasePath() async {
    if (kIsWeb) {
      return 'papyrus-powersync.db';
    }

    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'papyrus-powersync.db');
  }

  void _watchBooks(PowerSyncDatabase database) {
    unawaited(_booksSubscription?.cancel());
    _booksSubscription = database
        .watch('SELECT * FROM books ORDER BY added_at DESC', triggerOnTables: ['books'])
        .listen((rows) {
          final books = rows.map((row) => PowerSyncBookMapper.fromRow(Map<String, Object?>.from(row))).toList();
          dataStore.replaceBooksFromSync(books);
        });
  }
}
