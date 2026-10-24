import 'dart:typed_data';

import 'package:image/image.dart' as image;

const maxProfilePhotoBytes = 5 * 1024 * 1024;

/// Bounds decoding and strips source metadata before uploading a small JPEG.
Uint8List prepareProfilePhoto(Uint8List bytes) {
  if (bytes.length > maxProfilePhotoBytes) {
    throw const FormatException('Choose a photo smaller than 5 MB.');
  }

  try {
    return _preparePhoto(bytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('This photo could not be opened. Choose another image.');
  }
}

Uint8List _preparePhoto(Uint8List bytes) {
  image.Decoder? decoder;

  if (bytes.length >= 8) {
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      decoder = image.JpegDecoder();
    } else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) {
      decoder = image.PngDecoder();
    }
  }

  final info = decoder?.startDecode(bytes);

  if (info == null || info.width <= 0 || info.height <= 0 || info.width * info.height > 25000000) {
    throw const FormatException('Choose a JPEG or PNG photo up to 25 megapixels.');
  }

  final decoded = decoder!.decodeFrame(0);

  if (decoded == null) {
    throw const FormatException('This photo could not be opened. Choose another image.');
  }

  final oriented = image.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height ? oriented.width : oriented.height;
  final resized = longestSide > 512
      ? image.copyResize(
          oriented,
          width: (oriented.width * 512 / longestSide).round().clamp(1, 512),
          height: (oriented.height * 512 / longestSide).round().clamp(1, 512),
        )
      : oriented;

  final clean = image.Image(width: resized.width, height: resized.height, numChannels: 3);
  image.fill(clean, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(clean, resized);
  return image.encodeJpg(clean, quality: 90);
}
