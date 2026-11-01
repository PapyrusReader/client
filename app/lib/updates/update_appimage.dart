import 'dart:io';

import 'package:path/path.dart' as path;

Future<void> replaceAppImage(File target, File verifiedDownload) async {
  if (await FileSystemEntity.isLink(target.path) || !await target.exists()) {
    throw const FileSystemException('Update the original AppImage, not a symbolic link');
  }

  // Stage on the same filesystem so rename cannot leave a partial executable.
  final staging = await Directory(path.dirname(target.path)).createTemp('.papyrus-update-');

  try {
    final replacement = await verifiedDownload.copy(path.join(staging.path, 'Papyrus.AppImage'));
    final result = await Process.run('/bin/chmod', ['755', replacement.path]);

    if (result.exitCode != 0) {
      throw const FileSystemException('Cannot make the new AppImage executable');
    }

    await replacement.rename(target.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
