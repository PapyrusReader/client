import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/models/book.dart';

void main() {
  late MediaCacheService service;

  setUp(() {
    service = const MediaCacheService();
  });

  test('uses cached book file when its hash matches', () async {
    var downloads = 0;
    var writes = 0;
    final bytes = Uint8List.fromList('cached'.codeUnits);
    final book = _book(fileHash: service.sha256Hex(bytes), fileMediaId: 'asset-1');

    final result = await service.ensureBookFileCached(
      book,
      readLocalBookFile: (_) async => bytes,
      writeLocalBookFile: (_, _, _) async => writes++,
      downloadMedia: (_) async {
        downloads++;
        return Uint8List.fromList('remote'.codeUnits);
      },
    );

    expect(result, bytes);
    expect(downloads, 0);
    expect(writes, 0);
  });

  test('downloads and stores book file when local cache is missing', () async {
    Uint8List? written;
    String? writtenExtension;
    final remote = Uint8List.fromList('remote file'.codeUnits);
    final book = _book(fileHash: service.sha256Hex(remote), fileMediaId: 'asset-1', fileFormat: BookFormat.pdf);

    final result = await service.ensureBookFileCached(
      book,
      readLocalBookFile: (_) async => null,
      writeLocalBookFile: (_, extension, bytes) async {
        writtenExtension = extension;
        written = bytes;
      },
      downloadMedia: (assetId) async {
        expect(assetId, 'asset-1');
        return remote;
      },
    );

    expect(result, remote);
    expect(writtenExtension, 'pdf');
    expect(written, remote);
  });

  test('redownloads when cached hash does not match', () async {
    final stale = Uint8List.fromList('stale'.codeUnits);
    final remote = Uint8List.fromList('remote file'.codeUnits);
    final book = _book(fileHash: service.sha256Hex(remote), fileMediaId: 'asset-1');

    final result = await service.ensureBookFileCached(
      book,
      readLocalBookFile: (_) async => stale,
      writeLocalBookFile: (_, _, _) async {},
      downloadMedia: (_) async => remote,
    );

    expect(result, remote);
  });

  test('rejects downloaded bytes when expected hash does not match', () async {
    final book = _book(fileHash: List.filled(64, '0').join(), fileMediaId: 'asset-1');

    expect(
      () => service.ensureBookFileCached(
        book,
        readLocalBookFile: (_) async => null,
        writeLocalBookFile: (_, _, _) async {},
        downloadMedia: (_) async => Uint8List.fromList('wrong'.codeUnits),
      ),
      throwsStateError,
    );
  });
}

Book _book({required String fileHash, String? fileMediaId, BookFormat? fileFormat}) {
  return Book(
    id: 'book-1',
    title: 'Book',
    author: 'Author',
    filePath: 'book-1',
    fileSize: 12,
    fileHash: fileHash,
    fileFormat: fileFormat ?? BookFormat.epub,
    fileMediaId: fileMediaId,
    addedAt: DateTime.utc(2026),
  );
}
