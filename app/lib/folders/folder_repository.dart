import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

/// This database is never connected to a server or cleared with the sync cache.
class FolderRepository {
  FolderRepository(this.database);
  final PowerSyncDatabase database;
  static const leaseDuration = Duration(minutes: 2);

  static const schema = Schema([
    Table.localOnly('folders', [Column.text('json')]),
    Table.localOnly('files', [Column.text('folder_id'), Column.text('json')]),
    Table.localOnly('jobs', [Column.text('folder_id'), Column.text('json')]),
    Table.localOnly('exclusions', [Column.text('book_id')]),
    Table.localOnly('lease', [Column.text('owner'), Column.integer('expires')]),
    Table.localOnly('retired_grants', [Column.text('json')]),
    Table.localOnly('folder_books', [Column.text('folder_id'), Column.text('book_id')]),
  ]);

  static Future<FolderRepository> open(String scope, {String? databasePath}) async {
    final name = 'papyrus-folders-${sha256.convert(utf8.encode(scope))}.db';
    final location = databasePath ?? (kIsWeb ? name : path.join((await getApplicationSupportDirectory()).path, name));
    final database = PowerSyncDatabase(schema: schema, path: location);
    await database.initialize();
    await database.execute('''
      INSERT OR REPLACE INTO folder_books (id, folder_id, book_id)
      SELECT folder_id || ':' || json_extract(json, '\$.bookId'), folder_id, json_extract(json, '\$.bookId')
      FROM files WHERE json_extract(json, '\$.bookId') IS NOT NULL
    ''');
    return FolderRepository(database);
  }

  Future<Map<String, Set<String>>> bookIds() async {
    final result = <String, Set<String>>{};

    for (final row in await database.getAll('SELECT folder_id, book_id FROM folder_books')) {
      (result[row['folder_id'] as String] ??= {}).add(row['book_id'] as String);
    }

    return result;
  }

  Future<List<WatchedFolder>> folders() async => [
    for (final row in await database.getAll('SELECT json FROM folders ORDER BY id'))
      WatchedFolder.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
  ];

  Future<void> saveFolder(WatchedFolder folder) => save('folders', folder.id, folder.toJson());

  Future<void> replaceGrant(WatchedFolder folder, FolderGrant previous) =>
      database.writeTransaction((transaction) async {
        await transaction.execute('INSERT OR REPLACE INTO folders (id, json) VALUES (?, ?)', [
          folder.id,
          jsonEncode(folder.toJson()),
        ]);

        if (previous.key != folder.grant.key) {
          await transaction.execute('INSERT OR REPLACE INTO retired_grants (id, json) VALUES (?, ?)', [
            previous.key,
            jsonEncode(previous.toJson()),
          ]);
        }
      });

  Future<List<FolderGrant>> retiredGrants() async => [
    for (final row in await database.getAll('SELECT json FROM retired_grants'))
      FolderGrant.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
  ];

  Future<void> forgetGrant(String key) async => database.execute('DELETE FROM retired_grants WHERE id = ?', [key]);

  Future<Map<String, dynamic>?> get(String table, String id) async {
    _validateTable(table);
    final row = await database.getOptional('SELECT json FROM $table WHERE id = ?', [id]);
    return row == null ? null : jsonDecode(row['json'] as String) as Map<String, dynamic>;
  }

  Future<void> save(String table, String id, Map<String, dynamic> value, {String? folderId}) async {
    _validateTable(table);

    if (table == 'folders') {
      await database.execute('INSERT OR REPLACE INTO folders (id, json) VALUES (?, ?)', [id, jsonEncode(value)]);
    } else {
      await database.writeTransaction((transaction) async {
        await transaction.execute('INSERT OR REPLACE INTO $table (id, folder_id, json) VALUES (?, ?, ?)', [
          id,
          folderId,
          jsonEncode(value),
        ]);

        final bookId = value['bookId'];

        if (table == 'files' && bookId != null) {
          await transaction.execute('INSERT OR REPLACE INTO folder_books (id, folder_id, book_id) VALUES (?, ?, ?)', [
            '$folderId:$bookId',
            folderId,
            bookId,
          ]);
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> records(String table, {String? folderId}) async {
    _validateTable(table);
    final rows = await database.getAll(
      'SELECT id, json FROM $table${folderId == null ? '' : ' WHERE folder_id = ?'}',
      folderId == null ? [] : [folderId],
    );
    return [
      for (final row in rows) {...jsonDecode(row['json'] as String) as Map<String, dynamic>, 'recordId': row['id']},
    ];
  }

  Future<void> delete(String table, String id) async {
    _validateTable(table);
    await database.execute('DELETE FROM $table WHERE id = ?', [id]);
  }

  Future<void> exclude(String hash, String bookId) async {
    await database.execute('INSERT OR REPLACE INTO exclusions (id, book_id) VALUES (?, ?)', [hash, bookId]);
  }

  Future<bool> isExcluded(String hash) async =>
      await database.getOptional('SELECT id FROM exclusions WHERE id = ?', [hash]) != null;

  Future<void> allow(String hash) async => database.execute('DELETE FROM exclusions WHERE id = ?', [hash]);

  Future<bool> acquire(String owner, DateTime now) => database.writeTransaction((transaction) async {
    final lease = await transaction.getOptional('SELECT owner, expires FROM lease WHERE id = ?', ['scan']);

    if (lease != null && lease['owner'] != owner && (lease['expires'] as int) > now.millisecondsSinceEpoch) {
      return false;
    }

    await transaction.execute('INSERT OR REPLACE INTO lease (id, owner, expires) VALUES (?, ?, ?)', [
      'scan',
      owner,
      now.add(leaseDuration).millisecondsSinceEpoch,
    ]);
    return true;
  });

  Future<void> release(String owner) async =>
      database.execute('DELETE FROM lease WHERE id = ? AND owner = ?', ['scan', owner]);

  Future<void> removeFolder(String id) => database.writeTransaction((transaction) async {
    final row = await transaction.getOptional('SELECT json FROM folders WHERE id = ?', [id]);

    if (row != null) {
      final folder = WatchedFolder.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>);
      await transaction.execute('INSERT OR REPLACE INTO retired_grants (id, json) VALUES (?, ?)', [
        folder.grant.key,
        jsonEncode(folder.grant.toJson()),
      ]);
    }

    for (final table in ['files', 'jobs', 'folder_books']) {
      await transaction.execute('DELETE FROM $table WHERE folder_id = ?', [id]);
    }

    await transaction.execute('DELETE FROM folders WHERE id = ?', [id]);
  });

  Future<void> clear() => database.writeTransaction((transaction) async {
    for (final table in ['folders', 'files', 'jobs', 'exclusions', 'folder_books']) {
      await transaction.execute('DELETE FROM $table');
    }
  });

  Future<void> close() => database.close();

  void _validateTable(String table) {
    if (!const ['folders', 'files', 'jobs'].contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
  }
}
