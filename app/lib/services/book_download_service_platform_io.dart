import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> saveBookFileToDevice({
  required Uint8List bytes,
  required String fileName,
  required String extension,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Download book',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
  );

  if (path == null) return null;

  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes);
  }
  return path;
}
