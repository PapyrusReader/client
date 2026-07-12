import 'dart:convert';
import 'dart:typed_data';

/// Convert image bytes to a data URI string with auto-detected MIME type.
String bytesToDataUri(Uint8List bytes) {
  final mimeType = imageMimeType(bytes);
  final base64Data = base64Encode(bytes);
  return 'data:$mimeType;base64,$base64Data';
}

/// Detect the supported image MIME type from its signature.
String imageMimeType(Uint8List bytes) {
  if (bytes.length >= 8) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    } else if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      return 'image/webp';
    }
  }
  return 'image/jpeg';
}

/// Return a filename extension matching [imageMimeType].
String imageFileExtension(Uint8List bytes) {
  return switch (imageMimeType(bytes)) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
}
