import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/cover_storage_bucket.dart';
import 'package:papyrus/media/local_cover_image_provider.dart';
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
    _clearImageCache();
    root = await Directory.systemTemp.createTemp('papyrus-cover-cache-');
    PathProviderPlatform.instance = _FakePathProvider(root);
    service = BookImportService();
  });

  tearDown(() async {
    _clearImageCache();
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

  test('concurrent same-key stores leave one complete value and no temporary files', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final secondService = BookImportService();
    final candidates = List.generate(12, (index) => Uint8List.fromList(List.filled(4096, index)));

    await Future.wait(
      candidates.indexed.map(
        (candidate) => (candidate.$1.isEven ? service : secondService).storeCoverFile(scope, 'asset-1', candidate.$2),
      ),
    );

    final stored = await service.getCoverFile(scope, 'asset-1');
    expect(candidates.any((bytes) => _bytesEqual(bytes, stored)), isTrue);
    expect(
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp') || file.path.endsWith('.bak')),
      isEmpty,
    );
  });

  test('native replacement uses direct rename without moving the existing cache aside', () {
    final source = File('lib/services/book_import_service_stub.dart').readAsStringSync();
    final writer = source.substring(
      source.indexOf('Future<void> _writeCoverFile'),
      source.indexOf('Future<void> _removeCoverFile'),
    );

    expect(writer, contains('await tempFile.rename(file.path);'));
    expect(writer, isNot(contains('backupFile')));
    expect(writer, isNot(contains("await file.rename")));
  });

  test('pending store queued during promotion preserves the newer generation', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    await service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([1]));

    final promotion = service.promotePendingCoverFile(scope, bookId: 'book-1', mediaId: 'asset-1');
    final newerStore = service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([2]));
    await Future.wait([promotion, newerStore]);

    expect(await service.getCoverFile(scope, 'asset-1'), Uint8List.fromList([1]));
    expect(await service.getPendingCoverFile(scope, 'book-1'), Uint8List.fromList([2]));
  });

  test('deleting a cover is idempotent', () async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    await service.storeCoverFile(scope, 'asset-1', Uint8List.fromList([1]));

    await service.deleteCoverFile(scope, 'asset-1');
    await service.deleteCoverFile(scope, 'asset-1');

    expect(await service.getCoverFile(scope, 'asset-1'), isNull);
  });

  for (final deletion in <({String name, MediaStorageScope scope, CoverStorageBucket bucket, String id})>[
    (
      name: 'cached',
      scope: MediaStorageScope(profileKey: 'official', userId: 'user-1'),
      bucket: CoverStorageBucket.cached,
      id: 'asset-1',
    ),
    (
      name: 'pending',
      scope: MediaStorageScope(profileKey: 'official', userId: 'user-1'),
      bucket: CoverStorageBucket.pending,
      id: 'book-1',
    ),
    (name: 'guest', scope: MediaStorageScope.localGuest, bucket: CoverStorageBucket.guestBooks, id: 'book-1'),
  ]) {
    testWidgets('deleting a ${deletion.name} cover evicts its decoded image', (tester) async {
      var loads = 0;
      Future<Uint8List?> loadBytes() async {
        loads++;
        return _pngBytes;
      }

      await tester.runAsync(() => _storeCover(service, deletion.scope, deletion.bucket, deletion.id));
      await _pumpCover(tester, deletion.scope, deletion.bucket, deletion.id, loadBytes);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      await tester.runAsync(() => _deleteCover(service, deletion.scope, deletion.bucket, deletion.id));
      await _pumpCover(tester, deletion.scope, deletion.bucket, deletion.id, loadBytes);

      expect(loads, 2);
    });
  }

  testWidgets('promotion evicts pending decoded image but preserves cached target', (tester) async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    var pendingLoads = 0;
    var cachedLoads = 0;

    await tester.runAsync(() async {
      await service.storePendingCoverFile(scope, 'book-1', _pngBytes);
      await service.storeCoverFile(scope, 'asset-1', _pngBytes);
    });
    await _pumpCover(tester, scope, CoverStorageBucket.pending, 'book-1', () async {
      pendingLoads++;
      return _pngBytes;
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', () async {
      cachedLoads++;
      return _pngBytes;
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await tester.runAsync(() => service.promotePendingCoverFile(scope, bookId: 'book-1', mediaId: 'asset-1'));
    await _pumpCover(tester, scope, CoverStorageBucket.pending, 'book-1', () async {
      pendingLoads++;
      return _pngBytes;
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', () async {
      cachedLoads++;
      return _pngBytes;
    });

    expect(pendingLoads, 2);
    expect(cachedLoads, 1);
  });

  testWidgets('ordinary cover stores do not evict a decoded image', (tester) async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    var loads = 0;
    Future<Uint8List?> loadBytes() async {
      loads++;
      return _pngBytes;
    }

    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', loadBytes);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() => service.storeCoverFile(scope, 'asset-1', _pngBytes));
    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', loadBytes);

    expect(loads, 1);
  });

  testWidgets('filesystem deletion failure preserves a decoded image', (tester) async {
    final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    var loads = 0;
    Future<Uint8List?> loadBytes() async {
      loads++;
      return _pngBytes;
    }

    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', loadBytes);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final blocker = File('${root.path}/not-a-directory')..writeAsStringSync('blocked');
    PathProviderPlatform.instance = _FakePathProvider(Directory(blocker.path));
    await tester.runAsync(
      () => expectLater(service.deleteCoverFile(scope, 'asset-1'), throwsA(isA<FileSystemException>())),
    );
    await _pumpCover(tester, scope, CoverStorageBucket.cached, 'asset-1', loadBytes);

    expect(loads, 1);
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

    for (final action in ['getCover', 'storeCover', 'deleteCover', 'promoteCover', 'clearCovers']) {
      expect(source, contains("case '$action':"));
    }
    expect(source, contains("new Set(['cached', 'pending', 'books'])"));
    expect(source, contains("validateCoverBucket(bucket)"));
    expect(source, contains("getDirectoryHandle(bucket, { create })"));
    expect(source, contains('withCoverLocks('));
    expect(source, contains('navigator.locks.request'));
    expect(source, contains('coverLockName('));
  });

  test('book worker derives shared Web Lock names from cover keys', () async {
    final result = await Process.run('node', const [
      '-e',
      r'''
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('web/book_worker.js', 'utf8');
const requested = [];
const context = {
  self: {},
  postMessage() {},
  navigator: {
    locks: {
      async request(name, callback) {
        requested.push(name);
        return callback();
      },
    },
  },
};
vm.createContext(context);
vm.runInContext(source, context);
(async () => {
  const first = vm.runInContext("coverLockName('scope', 'pending', 'book-1')", context);
  const second = vm.runInContext("coverLockName('scope', 'pending', 'book-1')", context);
  const cached = vm.runInContext("coverLockName('scope', 'cached', 'asset-1')", context);
  await vm.runInContext(
    "withCoverLocks([['scope', 'pending', 'book-1'], ['scope', 'cached', 'asset-1']], async () => {})",
    context,
  );
  if (first !== second || first === cached) process.exit(1);
  if (requested.length !== 2 || requested[0] > requested[1]) process.exit(2);
  if (!requested.includes(first) || !requested.includes(cached)) process.exit(3);
})().catch(() => process.exit(4));
''',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('book worker rethrows cover storage failures other than not found', () async {
    final result = await Process.run('node', const [
      '-e',
      r'''
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('web/book_worker.js', 'utf8');
const failure = new Error('storage denied');
failure.name = 'NotAllowedError';
const context = {
  self: {},
  postMessage() {},
  navigator: {
    storage: {
      async getDirectory() {
        return { async getDirectoryHandle() { throw failure; } };
      },
    },
  },
};
vm.createContext(context);
vm.runInContext(source, context);
(async () => {
  const results = await Promise.allSettled([
    vm.runInContext("opfsReadCover('scope', 'cached', 'id')", context),
    vm.runInContext("opfsDeleteCover('scope', 'cached', 'id')", context),
    vm.runInContext("opfsClearCovers('scope')", context),
  ]);
  if (results.some((result) => result.status !== 'rejected')) process.exit(1);
})().catch(() => process.exit(2));
''',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
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

  test('web cover mutations evict only successfully removed decoded keys', () {
    final source = File('lib/services/book_import_service.dart').readAsStringSync();
    final deleteHelper = source.substring(
      source.indexOf('Future<void> _deleteCoverFile'),
      source.indexOf('Future<void> clearCoverFiles'),
    );
    final promotion = source.substring(
      source.indexOf('Future<void> promotePendingCoverFile'),
      source.indexOf('Future<Uint8List?> _getCoverFile'),
    );
    final storeHelper = source.substring(
      source.indexOf('Future<void> _storeCoverFile'),
      source.indexOf('Future<void> _deleteCoverFile'),
    );

    expect(source, contains("import 'package:papyrus/media/local_cover_image_provider.dart';"));
    expect(
      deleteHelper.indexOf("await _sendCoverRequest(type: 'deleteCover'"),
      lessThan(deleteHelper.indexOf('LocalCoverImageProvider.evictKey(')),
    );
    expect(deleteHelper, contains('scopeKey: scope.persistenceKey'));
    expect(deleteHelper, contains('bucket: bucket'));
    expect(deleteHelper, contains('fileId: id'));
    expect(
      promotion.indexOf("await _sendCoverRequest(\n      type: 'promoteCover'"),
      lessThan(promotion.indexOf('LocalCoverImageProvider.evictKey(')),
    );
    expect(promotion, contains('bucket: CoverStorageBucket.pending'));
    expect(promotion, contains('fileId: bookId'));
    expect(promotion, isNot(contains('fileId: mediaId')));
    expect(storeHelper, isNot(contains('LocalCoverImageProvider.evictKey(')));
  });
}

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> _storeCover(BookImportService service, MediaStorageScope scope, CoverStorageBucket bucket, String id) {
  return switch (bucket) {
    CoverStorageBucket.cached => service.storeCoverFile(scope, id, _pngBytes),
    CoverStorageBucket.pending => service.storePendingCoverFile(scope, id, _pngBytes),
    CoverStorageBucket.guestBooks => service.storeGuestCoverFile(id, _pngBytes),
  };
}

Future<void> _deleteCover(BookImportService service, MediaStorageScope scope, CoverStorageBucket bucket, String id) {
  return switch (bucket) {
    CoverStorageBucket.cached => service.deleteCoverFile(scope, id),
    CoverStorageBucket.pending => service.deletePendingCoverFile(scope, id),
    CoverStorageBucket.guestBooks => service.deleteGuestCoverFile(id),
  };
}

Future<void> _pumpCover(
  WidgetTester tester,
  MediaStorageScope scope,
  CoverStorageBucket bucket,
  String id,
  Future<Uint8List?> Function() loadBytes,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Image(
        image: LocalCoverImageProvider(
          scopeKey: scope.persistenceKey,
          bucket: bucket,
          fileId: id,
          loadBytes: loadBytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _clearImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();
}

bool _bytesEqual(Uint8List first, Uint8List? second) {
  if (second == null || first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
