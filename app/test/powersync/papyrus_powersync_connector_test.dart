import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:powersync/powersync.dart';

void main() {
  test('serializes CRUD entries for Papyrus upload endpoint', () {
    final batch = powerSyncUploadBatchFromCrud([
      CrudEntry(11, UpdateType.put, 'books', '11111111-1111-1111-1111-111111111111', 22, {
        'title': 'Book',
        'co_authors': jsonEncode(['Co Author']),
        'custom_metadata': jsonEncode({'file_format': 'epub'}),
      }),
    ]);

    expect(batch, [
      {
        'op_id': 11,
        'op': 'PUT',
        'type': 'books',
        'id': '11111111-1111-1111-1111-111111111111',
        'tx_id': 22,
        'data': {
          'title': 'Book',
          'co_authors': ['Co Author'],
          'custom_metadata': {'file_format': 'epub'},
        },
        'metadata': null,
        'old': null,
      },
    ]);
  });
}
