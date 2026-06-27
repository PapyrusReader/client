import 'dart:typed_data';

enum MediaKind {
  bookFile('book_file'),
  coverImage('cover_image');

  const MediaKind(this.apiValue);

  final String apiValue;

  static MediaKind fromApiValue(String value) {
    return MediaKind.values.firstWhere((kind) => kind.apiValue == value);
  }
}

class MediaUploadPayload {
  const MediaUploadPayload({
    required this.bookId,
    required this.kind,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String bookId;
  final MediaKind kind;
  final String filename;
  final String contentType;
  final Uint8List bytes;
}

class MediaAsset {
  const MediaAsset({
    required this.assetId,
    required this.ownerUserId,
    required this.bookId,
    required this.kind,
    required this.originalFilename,
    required this.contentType,
    required this.extension,
    required this.sizeBytes,
    required this.sha256,
    required this.storagePath,
  });

  final String assetId;
  final String ownerUserId;
  final String bookId;
  final MediaKind kind;
  final String originalFilename;
  final String contentType;
  final String extension;
  final int sizeBytes;
  final String sha256;
  final String storagePath;

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      assetId: json['asset_id'] as String,
      ownerUserId: json['owner_user_id'] as String,
      bookId: json['book_id'] as String,
      kind: MediaKind.fromApiValue(json['kind'] as String),
      originalFilename: json['original_filename'] as String,
      contentType: json['content_type'] as String,
      extension: json['extension'] as String,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String,
      storagePath: json['storage_path'] as String,
    );
  }
}

class MediaStorageUsage {
  const MediaStorageUsage({required this.usedBytes, required this.quotaBytes, required this.availableBytes});

  final int usedBytes;
  final int quotaBytes;
  final int availableBytes;

  factory MediaStorageUsage.fromJson(Map<String, dynamic> json) {
    return MediaStorageUsage(
      usedBytes: json['used_bytes'] as int,
      quotaBytes: json['quota_bytes'] as int,
      availableBytes: json['available_bytes'] as int,
    );
  }
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message, {this.storageFull = false});
  const MediaUploadException.storageFull() : this('Storage full', storageFull: true);

  final String message;
  final bool storageFull;

  @override
  String toString() => message;
}
