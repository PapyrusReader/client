import 'dart:typed_data';

import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_download_service_platform_io.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_download_service_platform_web.dart';

class BookDownloadService {
  const BookDownloadService();

  Future<BookDownloadResult> saveBookFile({required Book book, required Uint8List bytes}) async {
    final extension = _extensionFor(book);
    final fileName = '${_safeFileName(book.title)}.$extension';
    final path = await saveBookFileToDevice(bytes: bytes, fileName: fileName, extension: extension);

    if (path == null) {
      return const BookDownloadResult.cancelled();
    }
    return BookDownloadResult.saved(path);
  }

  String _extensionFor(Book book) {
    return book.fileFormat?.name ?? 'bin';
  }

  String _safeFileName(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.isEmpty ? 'book' : sanitized;
  }
}

class BookDownloadResult {
  const BookDownloadResult._({required this.saved, this.path});

  const BookDownloadResult.saved(String path) : this._(saved: true, path: path);

  const BookDownloadResult.cancelled() : this._(saved: false);

  final bool saved;
  final String? path;
}
