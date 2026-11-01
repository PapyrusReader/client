import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:path/path.dart' as path;

DirectoryAccess createDirectoryAccess() => NativeDirectoryAccess();

class NativeDirectoryAccess implements DirectoryAccess {
  NativeDirectoryAccess({TargetPlatform? platform}) : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;
  static const _channel = MethodChannel('papyrus/folders');
  bool get _usesGrants => const [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS].contains(_platform);

  @override
  bool get supportsWatching => true;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      final operation = _channel.invokeMethod<T>(method, arguments);
      return await (method == 'pick' ? operation : operation.timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw const FolderAccessException('unavailable', 'Source file unavailable offline or still being downloaded.');
    } on PlatformException catch (error) {
      throw FolderAccessException(error.code, error.message ?? 'Could not access this folder.');
    } on FileSystemException catch (error) {
      throw FolderAccessException('unavailable', error.message);
    }
  }

  @override
  Future<FolderGrant?> pick() async {
    if (_usesGrants) {
      final selected = await _invoke<Map>('pick');
      return selected == null ? null : FolderGrant.fromJson(Map<String, dynamic>.from(selected));
    }

    final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a book folder');

    if (selected == null) {
      return null;
    }

    final location = await Directory(selected).resolveSymbolicLinks();
    return FolderGrant(
      key: location,
      identity: _platform == TargetPlatform.windows ? location.toLowerCase() : location,
      name: path.basename(location),
      location: location,
    );
  }

  @override
  Future<bool> reconnect(FolderGrant grant) async {
    if (_usesGrants) {
      return await _invoke<bool>('restore', {'grant': grant.key}) ?? false;
    }

    return Directory(grant.key).exists();
  }

  @override
  Stream<FolderFile> enumerate(FolderGrant grant, {required bool recursive}) async* {
    if (_usesGrants) {
      final cursor = await _invoke<String>('start', {'grant': grant.key, 'recursive': recursive});

      try {
        while (true) {
          final batch = await _invoke<List>('next', {'cursor': cursor}) ?? [];

          if (batch.isEmpty) {
            break;
          }

          for (final entry in batch) {
            yield FolderFile.fromJson(Map<String, dynamic>.from(entry as Map));
          }
        }
      } finally {
        await _invoke<void>('close', {'cursor': cursor});
      }

      return;
    }

    Stream<FolderFile> walk(Directory directory) async* {
      await for (final entry in directory.list(followLinks: false)) {
        if (!includeFolderEntry(path.basename(entry.path))) {
          continue;
        }

        if (entry is Directory && recursive) {
          try {
            await for (final file in walk(entry)) {
              yield file;
            }
          } on FileSystemException {
            yield FolderFile(
              key: path.relative(entry.path, from: grant.key),
              name: path.basename(entry.path),
              size: 0,
              modified: 0,
              error: 'Could not read this subfolder.',
            );
          }
        } else if (entry is File) {
          final relative = path.relative(entry.path, from: grant.key);

          try {
            final info = await entry.stat();
            yield FolderFile(
              key: relative,
              name: path.basename(entry.path),
              size: info.size,
              modified: info.modified.millisecondsSinceEpoch,
            );
          } on FileSystemException {
            yield FolderFile(
              key: relative,
              name: path.basename(entry.path),
              size: 0,
              modified: 0,
              error: 'Could not read this file.',
            );
          }
        }
      }
    }

    try {
      await for (final file in walk(Directory(grant.key))) {
        yield file;
      }
    } on FileSystemException catch (error) {
      final denied = _platform == TargetPlatform.windows
          ? error.osError?.errorCode == 5
          : const [1, 13].contains(error.osError?.errorCode);
      throw FolderAccessException(
        denied ? 'access' : 'unavailable',
        denied
            ? 'Allow Papyrus to read this folder, then reconnect it.'
            : 'The folder is unavailable. Reconnect the drive or folder.',
      );
    }
  }

  Future<File> _file(FolderGrant grant, FolderFile file) async {
    final location = path.normalize(path.join(grant.key, file.key));

    if (!path.isWithin(grant.key, location) ||
        await FileSystemEntity.type(location, followLinks: false) != FileSystemEntityType.file) {
      throw const FolderAccessException('unavailable', 'The source file moved or is no longer a regular file.');
    }

    final resolved = await File(location).resolveSymbolicLinks();

    if (!path.isWithin(grant.key, resolved)) {
      throw const FolderAccessException('access', 'The file is outside the selected folder.');
    }

    return File(resolved);
  }

  @override
  Future<FolderFile> stat(FolderGrant grant, FolderFile file) async {
    if (_usesGrants) {
      final result = await _invoke<Map>('stat', {'grant': grant.key, 'key': file.key});
      return FolderFile.fromJson(Map<String, dynamic>.from(result!));
    }

    final info = await (await _file(grant, file)).stat();
    return FolderFile(key: file.key, name: file.name, size: info.size, modified: info.modified.millisecondsSinceEpoch);
  }

  @override
  Future<Uint8List> read(FolderGrant grant, FolderFile file) async {
    if (_usesGrants) {
      return (await _invoke<Uint8List>('read', {'grant': grant.key, 'key': file.key}))!;
    }

    return (await _file(grant, file)).readAsBytes();
  }

  @override
  Stream<void> changes(FolderGrant grant) async* {
    if (_platform == TargetPlatform.macOS) {
      final location = await _invoke<String>('watch', {'grant': grant.key});

      try {
        yield* Directory(location!).watch(recursive: true).map((_) {});
      } finally {
        await _invoke<void>('unwatch', {'grant': grant.key});
      }
    } else if (!_usesGrants) {
      yield* Directory(grant.key).watch(recursive: _platform != TargetPlatform.linux).map((_) {});
    }
  }

  @override
  Future<void> release(FolderGrant grant) async {
    if (_usesGrants) {
      await _invoke<void>('release', {'grant': grant.key});
    }
  }
}
