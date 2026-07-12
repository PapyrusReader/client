import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/utils/image_utils.dart';

void main() {
  test('detects the content type and extension of picked cover bytes', () {
    expect(imageMimeType(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'image/png');
    expect(imageFileExtension(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'png');
    expect(imageMimeType(Uint8List.fromList([0xff, 0xd8, 0xff])), 'image/jpeg');
    expect(imageFileExtension(Uint8List.fromList([0xff, 0xd8, 0xff])), 'jpg');
  });
}
