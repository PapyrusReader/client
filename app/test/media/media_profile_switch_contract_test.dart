import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile switch publishes its key with the replacement repository', () {
    final source = File('lib/main.dart').readAsStringSync();
    final handler = source.substring(
      source.indexOf('void _handleSyncSettingsChanged()'),
      source.indexOf('Future<void> _refreshMediaUsage()'),
    );

    expect(handler, contains('_switchActiveSyncProfile(nextProfileKey, nextConfig)'));
    expect(handler.indexOf('_activeProfileKey = nextProfileKey'), greaterThan(handler.indexOf('_buildAuthRepository')));
  });

  test('upload processing rechecks profile transition after scope activation', () {
    final source = File('lib/main.dart').readAsStringSync();
    final processor = source.substring(
      source.indexOf('Future<void> _processMediaUploads()'),
      source.indexOf('@override\n  Widget build'),
    );

    expect(RegExp(r'_switchingSyncProfile').allMatches(processor), hasLength(greaterThanOrEqualTo(2)));
    expect(processor, contains('!identical(repository, _authRepository)'));
  });

  test('production cover queue integration stores scoped bytes before metadata', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final processor = mainSource.substring(
      mainSource.indexOf('Future<void> _processMediaUploads()'),
      mainSource.indexOf('@override\n  Widget build'),
    );
    expect(processor, contains('readPendingCover: _bookImportService.getPendingCoverFile'));

    final importSource = File('lib/widgets/add_book/import_book_sheet.dart').readAsStringSync();
    final enqueue = importSource.substring(
      importSource.indexOf('Future<void> _enqueueOnlineMediaUploads'),
      importSource.indexOf('String _contentTypeForExtension'),
    );
    expect(enqueue, contains('final scope = queue.activeScope;'));
    expect(enqueue, contains("throw StateError('Cannot queue cover upload without an active media storage scope')"));
    expect(enqueue, contains('storePendingCoverFile(scope, book.id, coverImage)'));
    expect(enqueue.indexOf('storePendingCoverFile'), lessThan(enqueue.indexOf('queue.enqueueCover')));
    expect(enqueue, isNot(contains('bytes: coverImage')));
  });
}
