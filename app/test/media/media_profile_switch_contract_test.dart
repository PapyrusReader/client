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

  test('production import delegates scoped cover persistence and queueing to the commit boundary', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final processor = mainSource.substring(
      mainSource.indexOf('Future<void> _processMediaUploads()'),
      mainSource.indexOf('@override\n  Widget build'),
    );
    expect(processor, contains('readPendingCover: _bookImportService.getPendingCoverFile'));

    final importSource = File('lib/widgets/add_book/import_book_sheet.dart').readAsStringSync();
    final commitStart = importSource.indexOf('Future<void> _addToLibrary()');
    final commit = importSource.substring(commitStart, importSource.indexOf('@override\n  Widget build', commitStart));
    expect(commit, contains('final accountScope = isOnlineAccount ? queue.activeScope : null;'));
    expect(commit, contains("throw StateError('Cannot import account media without an active media storage scope')"));
    expect(commit, contains('storePendingCover: importService.storePendingCoverFile'));
    expect(commit, contains('storeGuestCover: importService.storeGuestCoverFile'));
    expect(commit, contains('enqueueBookFile: queue.enqueueBookFile'));
    expect(commit, contains('enqueueCover: queue.enqueueCover'));
    expect(commit, contains('accountScope: accountScope'));
    expect(commit, isNot(contains('bytesToDataUri')));
  });
}
