import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:papyrus/models/book.dart';

typedef LocalBookFileReader = Future<Uint8List?> Function(String bookId);
typedef LocalBookFileWriter = Future<void> Function(String bookId, String extension, Uint8List bytes);
typedef MediaDownloader = Future<Uint8List> Function(String assetId);

/// Coordinates lazy download and platform-local caching for private media.
class MediaCacheService {
  const MediaCacheService();

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

  String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  bool _matchesExpectedHash(Uint8List bytes, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    return sha256Hex(bytes) == expectedHash;
  }

  String _extensionFor(Book book) {
    return book.fileFormat?.name ?? 'bin';
  }
}
