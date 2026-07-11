import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';

typedef CoverMediaUploader = Future<MediaAsset> Function(MediaUploadPayload payload);
typedef PendingCoverPromoter =
    Future<void> Function(MediaStorageScope scope, {required String bookId, required String mediaId});
typedef CoverPromotionErrorHandler = void Function(Object error, StackTrace stackTrace);

/// Uploads one media payload and promotes a successfully uploaded cover into
/// the source device's persistent media cache.
///
/// Promotion is deliberately best-effort: once the server accepts the upload,
/// a local filesystem failure must not cause the same media to be uploaded
/// again. The normal lazy cache path can download it later by media ID.
Future<MediaAsset> uploadAndPersistCover({
  required MediaStorageScope scope,
  required MediaUploadPayload payload,
  required CoverMediaUploader uploadMedia,
  required PendingCoverPromoter promotePendingCover,
  required CoverPromotionErrorHandler onPromotionError,
}) async {
  final asset = await uploadMedia(payload);
  if (payload.kind != MediaKind.coverImage) return asset;

  try {
    await promotePendingCover(scope, bookId: payload.bookId, mediaId: asset.assetId);
  } catch (error, stackTrace) {
    onPromotionError(error, stackTrace);
  }
  return asset;
}
