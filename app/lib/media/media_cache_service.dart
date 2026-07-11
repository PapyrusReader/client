import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';

typedef LocalBookFileReader = Future<Uint8List?> Function(String bookId);
typedef LocalBookFileWriter = Future<void> Function(String bookId, String extension, Uint8List bytes);
typedef MediaDownloader = Future<Uint8List> Function(String assetId);
typedef LocalCoverReader = Future<Uint8List?> Function(MediaStorageScope scope, String mediaId);
typedef LocalCoverWriter = Future<void> Function(MediaStorageScope scope, String mediaId, Uint8List bytes);

/// Coordinates lazy download and platform-local caching for private media.
class MediaCacheService {
  final Map<String, Future<Uint8List>> _coverDownloads = {};

  /// Returns a cached book file when present and, if the book has a stored
  /// hash, the bytes match the expected hash.
  Future<Uint8List?> getValidCachedBookFile(Book book, {required LocalBookFileReader readLocalBookFile}) async {
    final cached = await readLocalBookFile(book.id);
    if (cached == null) return null;
    return _matchesExpectedHash(cached, book.fileHash) ? cached : null;
  }

  /// Returns local book bytes, downloading and caching private server media
  /// when needed.
  Future<Uint8List> ensureBookFileCached(
    Book book, {
    required LocalBookFileReader readLocalBookFile,
    required LocalBookFileWriter writeLocalBookFile,
    required MediaDownloader downloadMedia,
  }) async {
    final cached = await getValidCachedBookFile(book, readLocalBookFile: readLocalBookFile);
    if (cached != null) return cached;

    final mediaId = book.fileMediaId;
    if (mediaId == null || mediaId.isEmpty) {
      throw StateError('Book file is not available on this device or server.');
    }

    final downloaded = await downloadMedia(mediaId);
    if (!_matchesExpectedHash(downloaded, book.fileHash)) {
      throw StateError('Downloaded book file did not match the expected hash.');
    }

    await writeLocalBookFile(book.id, _extensionFor(book), downloaded);
    return downloaded;
  }

  /// Returns a scoped local cover, downloading and persisting it when absent.
  Future<Uint8List> ensureCoverCached({
    required MediaStorageScope scope,
    required String mediaId,
    required LocalCoverReader readLocalCover,
    required LocalCoverWriter writeLocalCover,
    required MediaDownloader downloadMedia,
  }) {
    final key = '${scope.persistenceKey}:$mediaId';
    final existing = _coverDownloads[key];
    if (existing != null) return existing;

    final operation = _loadAndPersistCover(
      scope: scope,
      mediaId: mediaId,
      readLocalCover: readLocalCover,
      writeLocalCover: writeLocalCover,
      downloadMedia: downloadMedia,
    );
    _coverDownloads[key] = operation;
    operation.then(
      (_) => _removeCoverOperation(key, operation),
      onError: (Object error, StackTrace stackTrace) => _removeCoverOperation(key, operation),
    );
    return operation;
  }

  Future<Uint8List> _loadAndPersistCover({
    required MediaStorageScope scope,
    required String mediaId,
    required LocalCoverReader readLocalCover,
    required LocalCoverWriter writeLocalCover,
    required MediaDownloader downloadMedia,
  }) async {
    final cached = await readLocalCover(scope, mediaId);
    if (cached != null) return cached;

    final downloaded = await downloadMedia(mediaId);
    await writeLocalCover(scope, mediaId, downloaded);
    return downloaded;
  }

  void _removeCoverOperation(String key, Future<Uint8List> operation) {
    if (identical(_coverDownloads[key], operation)) {
      _coverDownloads.remove(key);
    }
  }

  String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  bool _matchesExpectedHash(Uint8List bytes, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    return sha256Hex(bytes) == expectedHash;
  }

  String _extensionFor(Book book) {
    return book.fileFormat?.name ?? 'bin';
  }
}
