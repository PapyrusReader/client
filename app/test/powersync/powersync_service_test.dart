import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:path/path.dart' as path;
import 'package:powersync/powersync.dart';

class OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

Book _book(String id) {
  return Book(id: id, title: 'Persistent guest book', author: 'Author', addedAt: DateTime.utc(2026, 1, 1));
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('papyrus-powersync-test-');
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  PapyrusPowerSyncService service() {
    return PapyrusPowerSyncService(
      connectorFactory: OfflineConnector.new,
      connectAuthenticated: false,
      pathResolver: (mode) async =>
          path.join(directory.path, mode == LibraryDatabaseMode.guest ? 'guest.db' : 'account.db'),
    );
  }

  test('guest books persist when the service is reopened', () async {
    final first = service();
    await first.activateGuest();
    await first.upsert(_book('guest-book'));
    await first.close();

    final second = service();
    await second.activateGuest();

    expect((await second.getById('guest-book'))?.title, 'Persistent guest book');
    await second.close();
  });

  test('authenticated books are cleared on deactivation', () async {
    final first = service();
    await first.activateAuthenticated('user-one');
    await first.upsert(_book('account-book'));
    await first.deactivate();
    await first.close();

    final second = service();
    await second.activateAuthenticated('user-one');

    expect(await second.getById('account-book'), isNull);
    await second.close();
  });
}
