import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

Future<String?> saveBookFileToDevice({
  required Uint8List bytes,
  required String fileName,
  required String extension,
}) async {
  final blob = Blob(<JSAny>[bytes.toJS].toJS, BlobPropertyBag(type: _contentTypeForExtension(extension)));
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);

  return fileName;
}

String _contentTypeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'epub':
      return 'application/epub+zip';
    case 'pdf':
      return 'application/pdf';
    case 'mobi':
      return 'application/x-mobipocket-ebook';
    case 'azw3':
      return 'application/vnd.amazon.ebook';
    case 'cbz':
      return 'application/vnd.comicbook+zip';
    case 'cbr':
      return 'application/vnd.comicbook-rar';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}
