import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'cover_storage_bucket.dart';

@immutable
class LocalCoverImageKey {
  const LocalCoverImageKey({required this.scopeKey, required this.bucket, required this.fileId});

  final String scopeKey;
  final CoverStorageBucket bucket;
  final String fileId;

  @override
  bool operator ==(Object other) {
    return other is LocalCoverImageKey &&
        other.scopeKey == scopeKey &&
        other.bucket == bucket &&
        other.fileId == fileId;
  }

  @override
  int get hashCode => Object.hash(scopeKey, bucket, fileId);

  @override
  String toString() {
    return 'LocalCoverImageKey('
        'scopeKey: $scopeKey, bucket: $bucket, fileId: $fileId)';
  }
}

class LocalCoverImageProvider extends ImageProvider<LocalCoverImageKey> {
  LocalCoverImageProvider({
    required String scopeKey,
    required CoverStorageBucket bucket,
    required String fileId,
    required this.loadBytes,
  }) : key = LocalCoverImageKey(scopeKey: scopeKey, bucket: bucket, fileId: fileId);

  final LocalCoverImageKey key;
  final Future<Uint8List?> Function() loadBytes;

  @override
  Future<LocalCoverImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<LocalCoverImageKey>(key);
  }

  @override
  ImageStreamCompleter loadImage(LocalCoverImageKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: key.toString());
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await loadBytes();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Local cover file was not found');
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  static bool evictKey({required String scopeKey, required CoverStorageBucket bucket, required String fileId}) {
    return PaintingBinding.instance.imageCache.evict(
      LocalCoverImageKey(scopeKey: scopeKey, bucket: bucket, fileId: fileId),
      includeLive: true,
    );
  }
}
