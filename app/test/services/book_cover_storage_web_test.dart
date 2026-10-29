@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/cover_storage_bucket.dart';
import 'package:papyrus/media/local_cover_image_provider.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/services/book_import_service.dart';

@JS('eval')
external JSAny? _evaluate(JSString script);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = MediaStorageScope(profileKey: 'server', userId: 'alice');
  late BookImportService service;

  setUp(() {
    _evaluate(
      r'''
      globalThis.originalWorker = globalThis.Worker;
      globalThis.coverMessages = [];
      globalThis.failCoverRequest = false;
      globalThis.Worker = class extends EventTarget {
        postMessage(message, transfer = []) {
          const copied = structuredClone(message, {transfer});
          coverMessages.push(copied);
          queueMicrotask(() => this.dispatchEvent(new MessageEvent('message', {data: {
            requestId: copied.requestId,
            type: failCoverRequest ? 'error' : 'success',
            message: 'storage denied',
          }})));
        }
        terminate() {}
      };
    '''
          .toJS,
    );
    service = BookImportService();
  });

  tearDown(() {
    service.dispose();
    PaintingBinding.instance.imageCache.clear();
    _evaluate('globalThis.Worker = originalWorker; delete globalThis.originalWorker;'.toJS);
  });

  test('web cover transfer preserves caller buffers and sends the scoped bucket', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await service.storePendingCoverFile(scope, 'book', bytes);
    expect(bytes, [1, 2, 3]);

    expect(
      (_evaluate(
                r'''
        coverMessages.length === 1 &&
        coverMessages[0].type === 'storeCover' &&
        coverMessages[0].scopeKey === 'server--alice' &&
        coverMessages[0].bucket === 'pending' &&
        coverMessages[0].mediaId === 'book' &&
        String(new Uint8Array(coverMessages[0].fileData)) === '1,2,3'
      '''
                    .toJS,
              )
              as JSBoolean)
          .toDart,
      isTrue,
    );
  });

  test('web mutations evict only the successfully deleted cover key', () async {
    LocalCoverImageKey key(String user, CoverStorageBucket bucket, {String fileId = 'book'}) =>
        LocalCoverImageKey(scopeKey: 'server--$user', bucket: bucket, fileId: fileId);

    final pending = key('alice', CoverStorageBucket.pending);
    final cached = key('alice', CoverStorageBucket.cached, fileId: 'asset');
    final otherAccount = key('bob', CoverStorageBucket.pending);
    final cache = PaintingBinding.instance.imageCache;

    for (final key in [pending, cached, otherAccount]) {
      cache.putIfAbsent(key, () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
    }

    await service.storeCoverFile(scope, 'asset', Uint8List.fromList([2]));
    await service.storePendingCoverFile(scope, 'book', Uint8List.fromList([1]));
    await service.promotePendingCoverFile(scope, bookId: 'book', mediaId: 'asset');
    expect(cache.containsKey(pending), isTrue);
    expect(cache.containsKey(cached), isTrue);
    _evaluate('failCoverRequest = true'.toJS);
    await expectLater(service.deletePendingCoverFile(scope, 'book'), throwsException);
    expect(cache.containsKey(pending), isTrue);
    _evaluate('failCoverRequest = false'.toJS);
    await service.deletePendingCoverFile(scope, 'book');
    expect(cache.containsKey(pending), isFalse);
    expect(cache.containsKey(cached), isTrue);
    expect(cache.containsKey(otherAccount), isTrue);
  });
}
