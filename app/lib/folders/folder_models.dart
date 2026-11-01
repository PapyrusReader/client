import 'package:papyrus/folders/directory_access.dart';

enum FolderStatus { scanning, importing, upToDate, paused, accessNeeded, unavailable, attention }

class WatchedFolder {
  WatchedFolder({
    required this.id,
    required this.grant,
    this.customName,
    this.recursive = true,
    this.shelfId,
    this.enabled = true,
    this.status = FolderStatus.upToDate,
    this.lastScan,
    this.added = 0,
    this.duplicates = 0,
    this.unsupported = 0,
    this.error,
  });

  final String id;
  FolderGrant grant;
  String? customName;

  bool recursive;
  String? shelfId;
  bool enabled;
  FolderStatus status;
  DateTime? lastScan;
  int added;
  int duplicates;
  int unsupported;
  String? error;
  FolderImportProgress? progress;

  String get name => customName ?? grant.name;

  void restore(WatchedFolder saved) {
    grant = saved.grant;
    customName = saved.customName;
    recursive = saved.recursive;
    shelfId = saved.shelfId;
    enabled = saved.enabled;
    status = saved.status;
    lastScan = saved.lastScan;
    added = saved.added;
    duplicates = saved.duplicates;
    unsupported = saved.unsupported;
    error = saved.error;
  }

  String get statusLabel => switch (status) {
    FolderStatus.scanning => 'Scanning',
    FolderStatus.importing => 'Importing',
    FolderStatus.upToDate => 'Up to date',
    FolderStatus.paused => 'Paused',
    FolderStatus.accessNeeded => 'Access needed',
    FolderStatus.unavailable => 'Folder unavailable',
    FolderStatus.attention => 'Needs attention',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'grant': grant.toJson(),
    'customName': customName,
    'recursive': recursive,
    'shelf': shelfId,
    'enabled': enabled,
    'status': status.name,
    'lastScan': lastScan?.toIso8601String(),
    'added': added,
    'duplicates': duplicates,
    'unsupported': unsupported,
    'error': error,
  };

  factory WatchedFolder.fromJson(Map<String, dynamic> json) => WatchedFolder(
    id: json['id'] as String,
    grant: FolderGrant.fromJson(Map<String, dynamic>.from(json['grant'] as Map)),
    customName: json['customName'] as String?,
    recursive: json['recursive'] as bool,
    shelfId: json['shelf'] as String?,
    enabled: json['enabled'] as bool,
    status: FolderStatus.values.byName(json['status'] as String),
    lastScan: DateTime.tryParse(json['lastScan'] as String? ?? ''),
    added: json['added'] as int? ?? 0,
    duplicates: json['duplicates'] as int? ?? 0,
    unsupported: json['unsupported'] as int? ?? 0,
    error: json['error'] as String?,
  );
}

class FolderPreview {
  int supported = 0;
  int unsupported = 0;
  int bytes = 0;
  int unknownSizes = 0;
  int inaccessible = 0;
}

class FolderImportProgress {
  FolderImportProgress({required this.total});

  final int total;
  int processed = 0;

  int get remaining => total - processed;
  double get fraction => total == 0 ? 0 : processed / total;
  String get label => '$processed/$total processed ($remaining left)';
}
