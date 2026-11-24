import 'dart:io';

import 'package:flutter/services.dart';
import 'package:papyrus/updates/update_download.dart';
import 'package:papyrus/updates/update_appimage.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/updates/update_windows.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const _android = MethodChannel('com.papyrus.reader/updates');
Uri get updateManifestUri =>
    Uri.https('github.com', '/PapyrusReader/client/releases/latest/download/release-manifest.json');

Future<UpdateChannel> updateChannel() async {
  if (Platform.isAndroid) {
    return await _android.invokeMethod<String>('channel') == 'direct' ? UpdateChannel.apk : UpdateChannel.play;
  }

  if (Platform.isWindows) {
    final uninstaller = File(path.join(path.dirname(Platform.resolvedExecutable), 'unins000.exe'));
    return await uninstaller.exists() ? UpdateChannel.windows : UpdateChannel.manual;
  }

  if (Platform.isLinux) {
    final appImage = Platform.environment['APPIMAGE'];

    if (appImage != null && path.isAbsolute(appImage) && await File(appImage).exists()) {
      return UpdateChannel.appImage;
    }

    if (Platform.resolvedExecutable == '/opt/papyrus/papyrus') {
      return UpdateChannel.apt;
    }
  }

  return UpdateChannel.manual;
}

Future<int?> checkPlayUpdate() => _android.invokeMethod<int>('check');

Future<String> installUpdate(UpdateAsset? asset, void Function(double?) progress) async {
  final channel = await updateChannel();

  if (channel == UpdateChannel.play) {
    await _android.invokeMethod<void>('installPlay');
    return 'Follow Google Play to finish the update.';
  }

  if (asset == null) {
    throw StateError('No update package is available');
  }

  if (channel == UpdateChannel.apk && await _android.invokeMethod<bool>('canInstall') != true) {
    return 'Allow Papyrus to install updates in Android settings, then return and tap Update again.';
  }

  final temporary = await getTemporaryDirectory();
  final directory = await Directory(path.join(temporary.path, 'papyrus-updates')).create(recursive: true);
  final staging = await directory.createTemp('download-');
  final file = File(path.join(staging.path, asset.name));
  await downloadUpdate(asset, file, progress);

  if (channel == UpdateChannel.apk) {
    await _android.invokeMethod<void>('installApk', {'path': file.path});
    return 'Follow Android to finish the update. If permission was requested, enable it and tap Update again.';
  }

  if (channel == UpdateChannel.windows) {
    progress(1);
    await installWindowsUpdate(file, path.dirname(Platform.resolvedExecutable));
    return 'Restart Papyrus to finish updating.';
  }

  if (channel == UpdateChannel.appImage) {
    final target = File(Platform.environment['APPIMAGE']!);

    await replaceAppImage(target, file);
    await staging.delete(recursive: true);

    return 'Restart Papyrus to finish updating.';
  }

  throw StateError('This installation uses external updates');
}
