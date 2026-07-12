import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/cover_upload_persistence.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';

void main() {
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');

  test('successful cover upload promotes the pending file', () async {
    final calls = <String>[];
    final payload = _payload(MediaKind.coverImage);

    final result = await uploadAndPersistCover(
      scope: scope,
      payload: payload,
      uploadMedia: (_) async {
        calls.add('upload');
        return _asset(MediaKind.coverImage);
      },
      promotePendingCover: (actualScope, {required bookId, required mediaId}) async {
        calls.add('promote:${actualScope.persistenceKey}:$bookId:$mediaId');
      },
      onPromotionError: (_, _) => fail('promotion must not fail'),
    );

    expect(result.assetId, 'asset-1');
    expect(calls, ['upload', 'promote:official--user-1:book-1:asset-1']);
  });

  test('book-file upload does not touch cover storage', () async {
    var promotions = 0;

    final result = await uploadAndPersistCover(
      scope: scope,
      payload: _payload(MediaKind.bookFile),
      uploadMedia: (_) async => _asset(MediaKind.bookFile),
      promotePendingCover: (_, {required bookId, required mediaId}) async => promotions++,
      onPromotionError: (_, _) {},
    );

    expect(result.kind, MediaKind.bookFile);
    expect(promotions, 0);
  });

  test('promotion failure is reported without retrying successful upload', () async {
    var uploads = 0;
    Object? reported;

    final result = await uploadAndPersistCover(
      scope: scope,
      payload: _payload(MediaKind.coverImage),
      uploadMedia: (_) async {
        uploads++;
        return _asset(MediaKind.coverImage);
      },
      promotePendingCover: (_, {required bookId, required mediaId}) async {
        throw StateError('OPFS unavailable');
      },
      onPromotionError: (error, _) => reported = error,
    );

    expect(result.assetId, 'asset-1');
    expect(uploads, 1);
    expect(reported, isA<StateError>());
  });

  test('a throwing diagnostic reporter cannot turn upload success into a retry', () async {
    final result = await uploadAndPersistCover(
      scope: scope,
      payload: _payload(MediaKind.coverImage),
      uploadMedia: (_) async => _asset(MediaKind.coverImage),
      promotePendingCover: (_, {required bookId, required mediaId}) async {
        throw StateError('cache unavailable');
      },
      onPromotionError: (_, _) => throw StateError('reporter unavailable'),
    );

    expect(result.assetId, 'asset-1');
  });

  test('upload failure propagates without promotion', () async {
    var promotions = 0;

    await expectLater(
      uploadAndPersistCover(
        scope: scope,
        payload: _payload(MediaKind.coverImage),
        uploadMedia: (_) async => throw StateError('server unavailable'),
        promotePendingCover: (_, {required bookId, required mediaId}) async => promotions++,
        onPromotionError: (_, _) {},
      ),
      throwsStateError,
    );
    expect(promotions, 0);
  });
}

MediaUploadPayload _payload(MediaKind kind) {
  return MediaUploadPayload(
    bookId: 'book-1',
    kind: kind,
    filename: kind == MediaKind.coverImage ? 'cover.jpg' : 'book.epub',
    contentType: kind == MediaKind.coverImage ? 'image/jpeg' : 'application/epub+zip',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

MediaAsset _asset(MediaKind kind) {
  return MediaAsset(
    assetId: 'asset-1',
    ownerUserId: 'user-1',
    bookId: 'book-1',
    kind: kind,
    originalFilename: kind == MediaKind.coverImage ? 'cover.jpg' : 'book.epub',
    contentType: kind == MediaKind.coverImage ? 'image/jpeg' : 'application/epub+zip',
    extension: kind == MediaKind.coverImage ? 'jpg' : 'epub',
    sizeBytes: 3,
    sha256: 'hash',
    storagePath: 'path',
  );
}
