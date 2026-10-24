import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:papyrus/services/profile_photo.dart';

void main() {
  test('photo preparation resizes, removes metadata and produces a JPEG', () {
    final source = image.Image(width: 1200, height: 600);
    source.exif.imageIfd[0x010e] = image.IfdValueAscii('Private description');
    final prepared = prepareProfilePhoto(image.encodeJpg(source));
    final result = image.decodeJpg(prepared)!;
    expect(result.width, 512);
    expect(result.height, 256);
    expect(result.exif.imageIfd[0x010e], isNull);
    expect(prepared.length, lessThan(maxProfilePhotoBytes));
  });

  test('invalid and oversized photos are rejected before upload', () {
    expect(() => prepareProfilePhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    expect(() => prepareProfilePhoto(Uint8List(maxProfilePhotoBytes + 1)), throwsFormatException);
  });
}
