import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/papyrus_schema.dart';
import 'package:papyrus/powersync/powersync_book_mapper.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

typedef PowerSyncConnectorFactory = PowerSyncBackendConnector Function();
typedef LibraryDatabasePathResolver = Future<String> Function(LibraryDatabaseMode mode);

class PapyrusPowerSyncService implements BookRepository {
  final PowerSyncConnectorFactory connectorFactory;
  final LibraryDatabasePathResolver? pathResolver;
  final bool connectAuthenticated;

  final StreamController<List<Book>> _booksController = StreamController<List<Book>>.broadcast();
  final StreamController<SyncState> _syncStateController = StreamController<SyncState>.broadcast();

  PowerSyncDatabase? _database;
  StreamSubscription? _booksSubscription;
  StreamSubscription? _statusSubscription;
  Future<void>? _modeOperation;
  LibraryDatabaseMode? _mode;
  String? _authenticatedUserId;
  SyncState _syncState = const SyncState();

  PapyrusPowerSyncService({required this.connectorFactory, this.pathResolver, this.connectAuthenticated = true});

  LibraryDatabaseMode? get mode => _mode;
  SyncState get syncState => _syncState;
  Stream<SyncState> get syncStates => _syncStateController.stream;

  Future<void> activateGuest() => _switchMode(LibraryDatabaseMode.guest);

  Future<void> activateAuthenticated(String userId) {
    return _switchMode(LibraryDatabaseMode.authenticated, authenticatedUserId: userId);
  }

  Future<void> setOnline(bool online) async {
    await _modeOperation;
    if (_mode != LibraryDatabaseMode.authenticated) {
      throw StateError('Only authenticated libraries can connect to PowerSync');
    }
    final database = _requireDatabase();
    if (online) {
      await database.connect(connector: connectorFactory());
    } else {
      await database.disconnect();
    }
  }

  Future<void> deactivate({bool clearAuthenticated = true}) async {
    await _modeOperation;
    final previousMode = _mode;
    await _closeActive(clearAuthenticated: clearAuthenticated);
    if (clearAuthenticated && previousMode != LibraryDatabaseMode.authenticated) {
      await _clearStoredAuthenticatedDatabase();
    }
    _mode = null;
    _authenticatedUserId = null;
    _booksController.add(const []);
    _setSyncState(const SyncState());
  }

  @override
  Stream<List<Book>> watchAll() => _booksController.stream;

  @override
  Future<Book?> getById(String id) async {
    final database = _requireDatabase();
    final row = await database.getOptional('SELECT * FROM books WHERE id = ?', [id]);
    return row == null ? null : PowerSyncBookMapper.fromRow(Map<String, Object?>.from(row));
  }

  @override
  Future<void> upsert(Book book) async {
    final database = _requireDatabase();
    final row = PowerSyncBookMapper.toRow(book);
    final existing = await database.getOptional('SELECT id FROM books WHERE id = ?', [book.id]);
    if (existing == null) {
      await database.execute(PowerSyncBookMapper.insertSql(), PowerSyncBookMapper.rowParameters(row));
    } else {
      await database.execute(PowerSyncBookMapper.updateSql(), PowerSyncBookMapper.updateParameters(row));
    }
    await _refreshPendingWrites();
  }

  @override
  Future<void> delete(String id) async {
    final database = _requireDatabase();
    await database.execute('DELETE FROM books WHERE id = ?', [id]);
    await _refreshPendingWrites();
  }

  Future<void> close() async {
    await _modeOperation;
    await _closeActive(clearAuthenticated: false);
    await _booksController.close();
    await _syncStateController.close();
  }

  Future<void> _switchMode(LibraryDatabaseMode mode, {String? authenticatedUserId}) async {
    await _modeOperation;
    if (_mode == mode &&
        _database != null &&
        (mode == LibraryDatabaseMode.guest || _authenticatedUserId == authenticatedUserId)) {
      return;
    }

    final operation = _performModeSwitch(mode, authenticatedUserId);
    _modeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_modeOperation, operation)) {
        _modeOperation = null;
      }
    }
  }

  Future<void> _performModeSwitch(LibraryDatabaseMode mode, String? authenticatedUserId) async {
    await _closeActive(clearAuthenticated: _mode == LibraryDatabaseMode.authenticated);
    _mode = mode;
    _authenticatedUserId = authenticatedUserId;
    _booksController.add(const []);

    final database = PowerSyncDatabase(
      schema: mode == LibraryDatabaseMode.guest ? papyrusGuestSchema : papyrusAccountSchema,
      path: await _databasePath(mode),
    );
    await database.initialize();
    _database = database;
    _watchBooks(database);

    if (mode == LibraryDatabaseMode.authenticated && connectAuthenticated) {
      _watchStatus(database);
      await database.connect(connector: connectorFactory());
    } else {
      _setSyncState(const SyncState());
    }
  }

  void _watchBooks(PowerSyncDatabase database) {
    unawaited(_booksSubscription?.cancel());
    _booksSubscription = database
        .watch('SELECT * FROM books ORDER BY added_at DESC', triggerOnTables: ['books'])
        .listen((rows) {
          _booksController.add(rows.map((row) => PowerSyncBookMapper.fromRow(Map<String, Object?>.from(row))).toList());
        });
  }

  void _watchStatus(PowerSyncDatabase database) {
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = database.statusStream.listen((status) async {
      await _setStatusFromPowerSync(status);
    });
    unawaited(_setStatusFromPowerSync(database.currentStatus));
  }

  Future<void> _setStatusFromPowerSync(SyncStatus status) async {
    final pending = await _hasPendingWrites();
    _setSyncState(
      SyncState(
        connected: status.connected,
        connecting: status.connecting,
        uploading: status.uploading,
        downloading: status.downloading,
        hasPendingWrites: pending,
        lastSyncedAt: status.lastSyncedAt,
        uploadError: status.uploadError,
        downloadError: status.downloadError,
      ),
    );
  }

  Future<void> _refreshPendingWrites() async {
    final current = _syncState;
    _setSyncState(
      SyncState(
        connected: current.connected,
        connecting: current.connecting,
        uploading: current.uploading,
        downloading: current.downloading,
        hasPendingWrites: await _hasPendingWrites(),
        lastSyncedAt: current.lastSyncedAt,
        uploadError: current.uploadError,
        downloadError: current.downloadError,
      ),
    );
  }

  Future<bool> _hasPendingWrites() async {
    final database = _database;
    if (database == null || _mode != LibraryDatabaseMode.authenticated) {
      return false;
    }
    final row = await database.get('SELECT EXISTS(SELECT 1 FROM ps_crud) AS pending');
    return row['pending'] == 1;
  }

  void _setSyncState(SyncState state) {
    _syncState = state;
    if (!_syncStateController.isClosed) {
      _syncStateController.add(state);
    }
  }

  PowerSyncDatabase _requireDatabase() {
    final database = _database;
    if (database == null) {
      throw StateError('Library database is not active');
    }
    return database;
  }

  Future<void> _closeActive({required bool clearAuthenticated}) async {
    await _booksSubscription?.cancel();
    await _statusSubscription?.cancel();
    _booksSubscription = null;
    _statusSubscription = null;

    final database = _database;
    final mode = _mode;
    _database = null;
    if (database == null) {
      return;
    }

    if (mode == LibraryDatabaseMode.authenticated && clearAuthenticated) {
      await database.disconnectAndClear(clearLocal: true);
    } else if (mode == LibraryDatabaseMode.authenticated) {
      await database.disconnect();
    }
    await database.close();
  }

  Future<void> _clearStoredAuthenticatedDatabase() async {
    final database = PowerSyncDatabase(
      schema: papyrusAccountSchema,
      path: await _databasePath(LibraryDatabaseMode.authenticated),
    );
    await database.initialize();
    await database.disconnectAndClear(clearLocal: true);
    await database.close();
  }

  Future<String> _databasePath(LibraryDatabaseMode mode) async {
    final customResolver = pathResolver;
    if (customResolver != null) {
      return customResolver(mode);
    }

    final fileName = mode == LibraryDatabaseMode.guest ? 'papyrus-guest.db' : 'papyrus-account.db';
    if (kIsWeb) {
      return fileName;
    }
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, fileName);
  }
}
