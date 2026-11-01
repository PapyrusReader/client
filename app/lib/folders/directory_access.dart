import 'dart:typed_data';

class FolderAccessException implements Exception {
  const FolderAccessException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class FolderGrant {
  const FolderGrant({
    required this.key,
    required this.identity,
    required this.name,
    required this.location,
    this.persistent = true,
  });
  final String key;
  final String identity;
  final String name;
  final String location;
  final bool persistent;

  Map<String, dynamic> toJson() => {
    'key': key,
    'identity': identity,
    'name': name,
    'location': location,
    'persistent': persistent,
  };

  factory FolderGrant.fromJson(Map<String, dynamic> json) => FolderGrant(
    key: json['key'] as String,
    identity: json['identity'] as String,
    name: json['name'] as String,
    location: json['location'] as String,
    persistent: json['persistent'] as bool? ?? true,
  );
}

class FolderFile {
  const FolderFile({required this.key, required this.name, required this.size, required this.modified, this.error});
  final String key;
  final String name;

  /// Providers may omit the size. A negative value means it is unknown.
  final int size;
  final int modified;
  final String? error;

  String get stamp => '$size:$modified';

  factory FolderFile.fromJson(Map<String, dynamic> json) => FolderFile(
    key: json['key'] as String,
    name: json['name'] as String,
    size: (json['size'] as num?)?.toInt() ?? -1,
    modified: (json['modified'] as num?)?.toInt() ?? 0,
    error: json['error'] as String?,
  );
}

abstract interface class DirectoryAccess {
  bool get supportsWatching;
  Future<FolderGrant?> pick();
  Future<bool> reconnect(FolderGrant grant);
  Stream<FolderFile> enumerate(FolderGrant grant, {required bool recursive});
  Future<FolderFile> stat(FolderGrant grant, FolderFile file);
  Future<Uint8List> read(FolderGrant grant, FolderFile file);
  Stream<void> changes(FolderGrant grant);
  Future<void> release(FolderGrant grant);
}

bool includeFolderEntry(String name) =>
    !name.startsWith('.') &&
    !name.startsWith('~') &&
    !RegExp(r'\.(tmp|part|partial|crdownload|download)$', caseSensitive: false).hasMatch(name);
