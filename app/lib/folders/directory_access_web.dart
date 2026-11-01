import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:papyrus/folders/directory_access.dart';

@JS('papyrusFolders.call')
external JSPromise<JSAny?> _call(JSString method, JSString arguments);

@JS('papyrusFolders.canWatch')
external JSBoolean get _canWatch;

DirectoryAccess createDirectoryAccess() => WebDirectoryAccess();

class WebDirectoryAccess implements DirectoryAccess {
  @override
  bool get supportsWatching => _canWatch.toDart;

  Future<dynamic> _invoke(String method, [Map<String, dynamic> arguments = const {}]) async {
    final response = await _call(method.toJS, jsonEncode(arguments).toJS).toDart;

    if (response.isA<JSArrayBuffer>()) {
      return (response as JSArrayBuffer).toDart.asUint8List();
    }

    final result = jsonDecode((response as JSString).toDart) as Map<String, dynamic>;

    if (result['error'] != null) {
      throw FolderAccessException(result['code'] as String, result['error'] as String);
    }

    return result['value'];
  }

  @override
  Future<FolderGrant?> pick() async {
    final result = await _invoke('pick');
    return result == null ? null : FolderGrant.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<bool> reconnect(FolderGrant grant) async => await _invoke('restore', {'grant': grant.key}) as bool;

  @override
  Stream<FolderFile> enumerate(FolderGrant grant, {required bool recursive}) async* {
    final cursor = await _invoke('start', {'grant': grant.key, 'recursive': recursive});

    try {
      while (true) {
        final batch = await _invoke('next', {'cursor': cursor}) as List;

        if (batch.isEmpty) {
          break;
        }

        for (final entry in batch) {
          yield FolderFile.fromJson(entry as Map<String, dynamic>);
        }
      }
    } finally {
      await _invoke('close', {'cursor': cursor});
    }
  }

  @override
  Future<FolderFile> stat(FolderGrant grant, FolderFile file) async =>
      FolderFile.fromJson(await _invoke('stat', {'grant': grant.key, 'key': file.key}) as Map<String, dynamic>);

  @override
  Future<Uint8List> read(FolderGrant grant, FolderFile file) async =>
      await _invoke('read', {'grant': grant.key, 'key': file.key}) as Uint8List;

  @override
  Stream<void> changes(FolderGrant grant) => const Stream.empty();

  @override
  Future<void> release(FolderGrant grant) async => _invoke('release', {'grant': grant.key});
}
