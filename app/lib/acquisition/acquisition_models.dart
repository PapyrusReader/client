enum AcquisitionEndpointKind {
  qbittorrent,
  transmission,
  deluge,
  prowlarr,
  torznab,
  newznab,
  readarr,
  sonarr,
  radarr,
  lidarr,
  whisparr;

  String get apiValue => name;
}

class AcquisitionEndpoint {
  final String id;
  final String name;
  final AcquisitionEndpointKind kind;
  final Uri baseUrl;
  final bool enabled;

  const AcquisitionEndpoint({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.enabled,
  });

  factory AcquisitionEndpoint.fromJson(Map<String, dynamic> json) =>
      AcquisitionEndpoint(
        id: json['endpoint_id'] as String,
        name: json['name'] as String,
        kind: AcquisitionEndpointKind.values.byName(json['kind'] as String),
        baseUrl: Uri.parse(json['base_url'] as String),
        enabled: json['enabled'] as bool,
      );
}

class TorrentRelease {
  final String title;
  final String downloadUrl;
  final String protocol;
  final String indexer;
  final int? seeders;
  final int? sizeBytes;

  const TorrentRelease({
    required this.title,
    required this.downloadUrl,
    required this.protocol,
    required this.indexer,
    this.seeders,
    this.sizeBytes,
  });

  bool get isMagnet => downloadUrl.startsWith('magnet:');

  factory TorrentRelease.fromJson(Map<String, dynamic> json) => TorrentRelease(
    title: json['title'] as String,
    downloadUrl: json['download_url'] as String,
    protocol: json['protocol'] as String,
    indexer: json['indexer'] as String,
    seeders: json['seeders'] as int?,
    sizeBytes: json['size_bytes'] as int?,
  );
}
