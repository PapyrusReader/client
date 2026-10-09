import 'dart:convert';
import 'package:papyrus/powersync/tracking_schema_version.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/powersync/powersync_book_mapper.dart';
import 'package:papyrus/powersync/library_row_mapper.dart';
import 'package:powersync/powersync.dart';

class PapyrusPowerSyncConnector extends PowerSyncBackendConnector {
  final AuthRepository authRepository;
  final PapyrusApiConfig config;
  final Future<void> Function()? onUploadComplete;
  final bool Function()? supportsTracking;
  final int Function()? trackingSchemaVersion;

  PapyrusPowerSyncConnector({
    required this.authRepository,
    required this.config,
    this.onUploadComplete,
    this.supportsTracking,
    this.trackingSchemaVersion,
  });

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    try {
      final token = await authRepository.createPowerSyncToken();

      return PowerSyncCredentials(
        endpoint: config.powerSyncServiceUri.toString(),
        token: token.token,
        expiresAt: DateTime.now().add(Duration(seconds: token.expiresIn)),
      );
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        return null;
      }

      rethrow;
    }
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    while (true) {
      final transaction = await database.getNextCrudTransaction();

      if (transaction == null) {
        return;
      }

      final version = supportsTracking?.call() == false ? 0 : trackingSchemaVersion?.call() ?? 2;
      final deferred = <CrudEntry>[];

      for (final entry in transaction.crud.where((entry) => trackingTableNames.contains(entry.table))) {
        final raw = entry.opData?['payload'];
        final payload = raw is String ? Map<String, dynamic>.from(jsonDecode(raw) as Map) : <String, dynamic>{};

        if (requiredTrackingSchemaVersion(payload) > version) {
          deferred.add(entry);
        }
      }

      if (deferred.isNotEmpty) {
        await database.writeTransaction((tx) async {
          for (final entry in deferred) {
            final row = await tx.getOptional('SELECT payload FROM ${entry.table} WHERE id = ?', [entry.id]);
            final payload = row?['payload'] as String? ?? jsonEncode({'id': entry.id});

            await tx.execute(
              'INSERT OR REPLACE INTO tracking_staging (id, table_name, row_id, payload, deleted) VALUES (?, ?, ?, ?, ?)',
              ['${entry.table}:${entry.id}', entry.table, entry.id, payload, row == null ? 1 : 0],
            );
          }
        });
      }

      final batch = powerSyncUploadBatchFromCrud(transaction.crud.where((entry) => !deferred.contains(entry)).toList());

      if (batch.isEmpty) {
        await transaction.complete();
        continue;
      }

      await authRepository.uploadPowerSyncBatch(batch);
      await transaction.complete();
      await onUploadComplete?.call();
    }
  }
}

List<Map<String, dynamic>> powerSyncUploadBatchFromCrud(List<CrudEntry> entries) {
  return entries.map(powerSyncCrudEntryToJson).toList();
}

Map<String, dynamic> powerSyncCrudEntryToJson(CrudEntry entry) {
  final json = entry.toJson();

  if (entry.table == 'books') {
    json['data'] = PowerSyncBookMapper.decodeUploadData(entry.opData);
  } else if (entry.opData != null) {
    json['data'] = decodeLibraryRow(entry.opData!);
  }

  return json;
}
