import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/cover_storage_bucket.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

void main() {
  late Directory root;
  late BookImportService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('papyrus-cover-cache-');
    PathProviderPlatform.instance = _FakePathProvider(root);
    service = BookImportService();
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('cover storage is isolated by server and user scope', () async {
    final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final second = MediaStorageScope(profileKey: 'official', userId: 'user-2');
    final bytes = Uint8List.fromList([1, 2, 3]);

    await service.storeCoverFile(first, 'asset-1', bytes);

    expect(await service.getCoverFile(first, 'asset-1'), bytes);
    expect(await service.getCoverFile(second, 'asset-1'), isNull);
  });

  test('cached and pending covers use separate bucket files', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

    await service.storeCoverFile(scope, 'shared-id', Uint8List.fromList([1]));
    await service.storePendingCoverFile(scope, 'shared-id', Uint8List.fromList([2]));

    expect(await service.getCoverFile(scope, 'shared-id'), Uint8List.fromList([1]));
    expect(await service.getPendingCoverFile(scope, 'shared-id'), Uint8List.fromList([2]));
    expect(
      File(
        '${root.path}/media-covers/${scope.persistenceKey}/'
        '${CoverStorageBucket.cached.pathComponent}/shared-id.bin',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${root.path}/media-covers/${scope.persistenceKey}/'
        '${CoverStorageBucket.pending.pathComponent}/shared-id.bin',
      ).existsSync(),
      isTrue,
    );
  });

  test('guest covers use the local guest books namespace', () async {
    await service.storeGuestCoverFile('book-1', Uint8List.fromList([3, 4]));

    expect(await service.getGuestCoverFile('book-1'), Uint8List.fromList([3, 4]));
    expect(
      File(
        '${root.path}/media-covers/${MediaStorageScope.localGuest.persistenceKey}/'
        '${CoverStorageBucket.guestBooks.pathComponent}/book-1.bin',
      ).existsSync(),
      isTrue,
    );

    await service.deleteGuestCoverFile('book-1');
    await service.deleteGuestCoverFile('book-1');
    expect(await service.getGuestCoverFile('book-1'), isNull);
  });

  test('promoting pending cover writes cache before removing pending', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    await service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([5, 6]));

    await service.promotePendingCoverFile(scope, bookId: 'book-1', mediaId: 'asset-1');

    expect(await service.getCoverFile(scope, 'asset-1'), Uint8List.fromList([5, 6]));
    expect(await service.getPendingCoverFile(scope, 'book-1'), isNull);
  });

  test('deleting pending covers is idempotent', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

    await service.deletePendingCoverFile(scope, 'book-1');
    await service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([7]));
    await service.deletePendingCoverFile(scope, 'book-1');
    await service.deletePendingCoverFile(scope, 'book-1');

    expect(await service.getPendingCoverFile(scope, 'book-1'), isNull);
  });

  test('storing a cover atomically replaces existing bytes', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

    await service.storeCoverFile(scope, 'asset-1', Uint8List.fromList([1, 2, 3]));
    await service.storeCoverFile(scope, 'asset-1', Uint8List.fromList([4, 5]));

    expect(await service.getCoverFile(scope, 'asset-1'), Uint8List.fromList([4, 5]));
    expect(root.listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.tmp')), isEmpty);
  });

  test('deleting a cover is idempotent', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    await service.storeCoverFile(scope, 'asset-1', Uint8List.fromList([1]));

    await service.deleteCoverFile(scope, 'asset-1');
    await service.deleteCoverFile(scope, 'asset-1');

    expect(await service.getCoverFile(scope, 'asset-1'), isNull);
  });

  test('clearing covers removes only the selected scope', () async {
    final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final second = MediaStorageScope(profileKey: 'official', userId: 'user-2');

    await service.storeCoverFile(first, 'asset-1', Uint8List.fromList([1]));
    await service.storePendingCoverFile(first, 'book-1', Uint8List.fromList([3]));
    await service.storeCoverFile(second, 'asset-2', Uint8List.fromList([2]));
    await service.clearCoverFiles(first);

    expect(await service.getCoverFile(first, 'asset-1'), isNull);
    expect(await service.getPendingCoverFile(first, 'book-1'), isNull);
    expect(await service.getCoverFile(second, 'asset-2'), Uint8List.fromList([2]));
  });

  test('cover storage rejects unsafe media ids', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

    expect(() => service.storeCoverFile(scope, '../asset', Uint8List.fromList([1])), throwsArgumentError);
    expect(() => service.storePendingCoverFile(scope, r'book\1', Uint8List.fromList([1])), throwsArgumentError);
    expect(() => service.storeGuestCoverFile('../book', Uint8List.fromList([1])), throwsArgumentError);
  });

  test('book worker declares scoped bucket cover actions and validates buckets', () {
    final source = File('web/book_worker.js').readAsStringSync();

    for (final action in ['getCover', 'storeCover', 'deleteCover', 'clearCovers']) {
      expect(source, contains("case '$action':"));
    }
    expect(source, contains("new Set(['cached', 'pending', 'books'])"));
    expect(source, contains("validateCoverBucket(bucket)"));
    expect(source, contains("getDirectoryHandle(bucket, { create })"));
  });

  test('web cover writes transfer a copy so caller bytes remain renderable', () {
    final source = File('lib/services/book_import_service.dart').readAsStringSync();
    final helper = source.substring(
      source.indexOf('Future<JSObject> _sendCoverRequest'),
      source.indexOf('BookImportResult _parseImportResult'),
    );

    expect(helper, contains('final actualBytes = Uint8List.fromList(bytes);'));
    expect(helper, contains("message['bucket'] = bucket.pathComponent.toJS;"));
    expect(helper, isNot(contains('bytes.offsetInBytes == 0 && bytes.lengthInBytes == bytes.buffer.lengthInBytes')));
  });
}
