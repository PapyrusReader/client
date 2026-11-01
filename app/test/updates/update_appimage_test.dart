import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/updates/update_appimage.dart';

void main() {
  test('AppImage replacement preserves other files and leaves an executable', () async {
    final directory = await Directory.systemTemp.createTemp('papyrus-appimage-test');
    addTearDown(() => directory.delete(recursive: true));
    final image = await File('${directory.path}/Papyrus.AppImage').writeAsString('old');
    final download = await File('${directory.path}/download').writeAsString('new');
    final library = await File('${directory.path}/books.sqlite').writeAsString('durable');
    await replaceAppImage(image, download);
    expect(await image.readAsString(), 'new');
    expect(await library.readAsString(), 'durable');
    expect((await image.stat()).mode & 0x49, 0x49);
    expect(await directory.list().length, 3);
  }, skip: Platform.isWindows);

  test('missing replacement and symbolic targets preserve the original image', () async {
    final directory = await Directory.systemTemp.createTemp('papyrus-appimage-test');
    addTearDown(() => directory.delete(recursive: true));
    final image = await File('${directory.path}/Papyrus.AppImage').writeAsString('old');
    await expectLater(replaceAppImage(image, File('${directory.path}/missing')), throwsA(isA<FileSystemException>()));
    expect(await image.readAsString(), 'old');
    final link = await Link('${directory.path}/link').create(image.path);
    await expectLater(replaceAppImage(File(link.path), image), throwsA(isA<FileSystemException>()));
    expect(await image.readAsString(), 'old');
  }, skip: Platform.isWindows);
}
