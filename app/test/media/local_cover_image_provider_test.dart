import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/cover_storage_bucket.dart';
import 'package:papyrus/media/local_cover_image_provider.dart';

void main() {
  setUp(_clearImageCache);
  tearDown(_clearImageCache);

  testWidgets('equal local cover keys reuse one filesystem load', (tester) async {
    var loads = 0;

    final first = _provider(
      loadBytes: () async {
        loads++;
        return _pngBytes;
      },
    );
    final second = _provider(
      loadBytes: () async {
        loads++;
        return _pngBytes;
      },
    );

    await _pumpImage(tester, first);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpImage(tester, second);

    expect(loads, 1);
  });

  test('scope, bucket, and file ID participate in key equality', () {
    final key = _provider().key;

    expect(_provider().key, key);
    expect(_provider(scopeKey: 'official--user-2').key, isNot(key));
    expect(_provider(bucket: CoverStorageBucket.pending).key, isNot(key));
    expect(_provider(fileId: 'asset-2').key, isNot(key));
  });

  testWidgets('null bytes surface an image-stream error', (tester) async {
    Object? streamError;
    final stream = _provider(loadBytes: () async => null).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (_, _) {},
      onError: (Object error, StackTrace? stackTrace) {
        streamError = error;
      },
    );

    stream.addListener(listener);
    await tester.pump();
    await tester.pump();
    stream.removeListener(listener);

    expect(streamError, isA<StateError>());
  });

  testWidgets('evicting a key makes an equal provider load again', (tester) async {
    var loads = 0;
    Future<Uint8List?> load() async {
      loads++;
      return _pngBytes;
    }

    await _pumpImage(tester, _provider(loadBytes: load));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(
      LocalCoverImageProvider.evictKey(
        scopeKey: 'official--user-1',
        bucket: CoverStorageBucket.cached,
        fileId: 'asset-1',
      ),
      isTrue,
    );

    await _pumpImage(tester, _provider(loadBytes: load));

    expect(loads, 2);
  });
}

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

LocalCoverImageProvider _provider({
  String scopeKey = 'official--user-1',
  CoverStorageBucket bucket = CoverStorageBucket.cached,
  String fileId = 'asset-1',
  Future<Uint8List?> Function()? loadBytes,
}) {
  return LocalCoverImageProvider(
    scopeKey: scopeKey,
    bucket: bucket,
    fileId: fileId,
    loadBytes: loadBytes ?? () async => _pngBytes,
  );
}

Future<void> _pumpImage(WidgetTester tester, LocalCoverImageProvider provider) async {
  await tester.pumpWidget(MaterialApp(home: Image(image: provider)));
  await tester.pumpAndSettle();
}

void _clearImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();
}
