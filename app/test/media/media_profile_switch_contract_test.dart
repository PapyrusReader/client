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

  test('successful cover upload promotes the captured pending cover best effort', () {
    final source = File('lib/main.dart').readAsStringSync();
    final processor = source.substring(
      source.indexOf('Future<void> _processMediaUploads()'),
      source.indexOf('@override\n  Widget build'),
    );

    expect(processor, contains('uploadAndPersistCover('));
    expect(processor, contains('scope: scope'));
    expect(processor, contains('promotePendingCover: _bookImportService.promotePendingCoverFile'));
    expect(processor, contains("library: 'papyrus cover promotion'"));
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
    expect(commit, contains('deletePendingCover: importService.deletePendingCoverFile'));
    expect(commit, contains('deleteGuestCover: importService.deleteGuestCoverFile'));
    expect(commit, contains('final bookRepository = dataStore.requireBookRepository();'));
    expect(commit, contains('dataStore.addBookToRepositoryAndWait(bookRepository, book)'));
    expect(commit, contains('dataStore.deleteBookFromRepositoryAndWait(bookRepository, bookId)'));
    expect(commit, contains('enqueueImportedBookMedia: queue.enqueueImportedBookMedia'));
    expect(commit, contains('isLibraryContextCurrent: ()'));
    expect(commit, contains('dataStore.isBookRepositoryCurrent(bookRepository)'));
    expect(commit, contains('queue.activeScope == accountScope'));
    expect(commit, contains('accountScope: accountScope'));
    expect(commit, isNot(contains('bytesToDataUri')));
  });

  test('import commit guard prevents repeat commits and disables mutable actions', () {
    final source = File('lib/widgets/add_book/import_book_sheet.dart').readAsStringSync();
    final commitStart = source.indexOf('Future<void> _addToLibrary()');
    final commit = source.substring(commitStart, source.indexOf('@override\n  Widget build', commitStart));

    expect(commit, contains('if (_committing) return;'));
    expect(commit, contains('_committing = true'));
    expect(commit, contains('_committing = false'));
    expect(source, contains('onPressed: _committing ? null : _addToLibrary'));
    expect(RegExp(r'onPressed: _committing \? null : _pickAndProcess').allMatches(source), hasLength(2));
    expect(source, contains('onPressed: _committing\n                    ? null'));
  });
}
