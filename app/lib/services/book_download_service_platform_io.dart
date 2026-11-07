import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> saveBookFileToDevice({
  required Uint8List bytes,
  required String fileName,
  required String extension,
}) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Download book',
    fileName: fileName,
    bytes: bytes,
  );

  if (uri == null) {
    return null;
  }

  return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
}
