import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncServerType { official, custom }

typedef DataSyncDiscoveryFetcher = Future<DataSyncDiscoverySettings> Function(Uri serverUrl);

class SyncSettingsException implements Exception {
  const SyncSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DataSyncDiscoverySettings {
  const DataSyncDiscoverySettings({required this.dataSyncUri, required this.fileStorageQuotaBytes});

  final Uri dataSyncUri;
  final int? fileStorageQuotaBytes;

  factory DataSyncDiscoverySettings.fromJson(Map<String, dynamic> json) {
    final dataSyncUrl = json['data_sync_url'] as String?;
    if (dataSyncUrl == null || dataSyncUrl.trim().isEmpty) {
      throw const SyncSettingsException('Server did not provide data sync settings');
    }

    final fileStorage = json['file_storage'];
    final quotaBytes = fileStorage is Map<String, dynamic> ? fileStorage['quota_bytes'] as int? : null;

    return DataSyncDiscoverySettings(dataSyncUri: Uri.parse(dataSyncUrl), fileStorageQuotaBytes: quotaBytes);
  }
}

class CustomSyncServer {
  const CustomSyncServer({
    required this.id,
    required this.url,
    required this.label,
    required this.dataSyncUri,
    required this.fileStorageQuotaBytes,
  });

  final String id;
  final String url;
  final String label;
  final Uri dataSyncUri;
  final int? fileStorageQuotaBytes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'label': label,
      'data_sync_url': dataSyncUri.toString(),
      'file_storage_quota_bytes': fileStorageQuotaBytes,
    };
  }

  factory CustomSyncServer.fromJson(Map<String, dynamic> json) {
    return CustomSyncServer(
      id: json['id'] as String,
      url: json['url'] as String,
      label: json['label'] as String,
      dataSyncUri: Uri.parse(json['data_sync_url'] as String),
      fileStorageQuotaBytes: json['file_storage_quota_bytes'] as int?,
    );
  }
}

class SyncSettingsProvider extends ChangeNotifier {
  static const officialServerId = 'official';
  static const officialFileStorageQuotaBytes = 1_073_741_824;

  static const _keyActiveServerId = 'sync_active_server_id';
  static const _keyCustomServers = 'sync_custom_servers';
  static const _legacyKeyServerType = 'sync_server_type';
  static const _legacyKeyCustomApiUrl = 'sync_custom_api_url';
  static const _legacyKeyCustomPowerSyncUrl = 'sync_custom_powersync_url';

  final SharedPreferences _prefs;
  final DataSyncDiscoveryFetcher _discoveryFetcher;
  final PapyrusApiConfig officialConfig;

  SyncSettingsProvider(this._prefs, {required this.officialConfig, DataSyncDiscoveryFetcher? discoveryFetcher})
    : _discoveryFetcher = discoveryFetcher ?? _fetchDataSyncSettings {
    _migrateLegacyCustomServer();
  }

  String get activeServerId {
    final id = _prefs.getString(_keyActiveServerId) ?? officialServerId;
    if (id == officialServerId || customServers.any((server) => server.id == id)) {
      return id;
    }
    return officialServerId;
  }

  List<CustomSyncServer> get customServers {
    final raw = _prefs.getString(_keyCustomServers);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => CustomSyncServer.fromJson(item as Map<String, dynamic>)).toList(growable: false);
  }

  CustomSyncServer? get activeCustomServer {
    final id = activeServerId;
    if (id == officialServerId) return null;
    for (final server in customServers) {
      if (server.id == id) return server;
    }
    return null;
  }

  String get activeServerLabel => activeCustomServer?.label ?? 'Official server';

  String get activeServerUrl => activeCustomServer?.url ?? officialConfig.serverBaseUri.toString();

  PapyrusApiConfig get activeApiConfig {
    final customServer = activeCustomServer;
    if (customServer == null) return officialConfig;

    return PapyrusApiConfig(serverBaseUri: Uri.parse(customServer.url), powerSyncServiceUri: customServer.dataSyncUri);
  }

  String get activeProfileKey {
    final customServer = activeCustomServer;
    if (customServer == null) return officialServerId;

    final digest = sha256.convert(utf8.encode(customServer.url)).toString();
    return 'custom-${digest.substring(0, 16)}';
  }

  int? get fileStorageQuotaBytes {
    return activeCustomServer?.fileStorageQuotaBytes ?? officialFileStorageQuotaBytes;
  }

  String fileStorageLabel({required int usedBytes, int? quotaBytesOverride}) {
    final quotaBytes = quotaBytesOverride ?? fileStorageQuotaBytes;
    if (quotaBytes == null) return '${_formatBytes(usedBytes)} used';

    final availableBytes = quotaBytes > usedBytes ? quotaBytes - usedBytes : 0;
    return '${_formatBytes(usedBytes)} used, ${_formatBytes(availableBytes)} available of ${_formatBytes(quotaBytes)}';
  }

  bool get isOfficialServer => activeServerId == officialServerId;

  Future<CustomSyncServer> addCustomServer(String url) async {
    final serverUri = _normalizeServerUri(url);
    final normalizedUrl = serverUri.toString();
    final servers = customServers;
    if (servers.any((server) => server.url == normalizedUrl)) {
      throw const SyncSettingsException('This custom server already exists');
    }

    final settings = await _discoveryFetcher(serverUri);
    final server = _customServerFromDiscovery(serverUri, settings);
    _saveCustomServers([...servers, server]);
    _setActiveServerId(server.id);
    notifyListeners();
    return server;
  }

  Future<CustomSyncServer> updateCustomServer(String id, String url) async {
    final servers = customServers;
    final index = servers.indexWhere((server) => server.id == id);
    if (index == -1) throw const SyncSettingsException('Custom server was not found');

    final serverUri = _normalizeServerUri(url);
    final normalizedUrl = serverUri.toString();
    if (servers.any((server) => server.id != id && server.url == normalizedUrl)) {
      throw const SyncSettingsException('This custom server already exists');
    }

    final settings = await _discoveryFetcher(serverUri);
    final updated = _customServerFromDiscovery(serverUri, settings);
    final nextServers = [...servers]..[index] = updated;
    _saveCustomServers(nextServers);
    if (activeServerId == id) _setActiveServerId(updated.id);
    notifyListeners();
    return updated;
  }

  void selectServer(String id) {
    if (id != officialServerId && !customServers.any((server) => server.id == id)) {
      throw const SyncSettingsException('Custom server was not found');
    }

    _setActiveServerId(id);
    notifyListeners();
  }

  void removeCustomServer(String id) {
    final nextServers = customServers.where((server) => server.id != id).toList(growable: false);
    if (nextServers.length == customServers.length) {
      throw const SyncSettingsException('Custom server was not found');
    }

    _saveCustomServers(nextServers);
    if (activeServerId == id) _setActiveServerId(officialServerId);
    notifyListeners();
  }

  @Deprecated('Use activeServerId instead.')
  SyncServerType get serverType => activeServerId == officialServerId ? SyncServerType.official : SyncServerType.custom;

  @Deprecated('Use selectServer instead.')
  set serverType(SyncServerType value) {
    if (value == SyncServerType.official) {
      selectServer(officialServerId);
      return;
    }
    if (customServers.isEmpty) {
      throw const SyncSettingsException('Custom server was not found');
    }
    selectServer(customServers.first.id);
  }

  @Deprecated('Use customServers instead.')
  String get customApiUrl => activeCustomServer?.url ?? '';

  @Deprecated('Use customServers instead.')
  String get customPowerSyncUrl => activeCustomServer?.dataSyncUri.toString() ?? '';

  @Deprecated('Use addCustomServer instead.')
  void setCustomServerUrls({required String apiUrl, required String powerSyncUrl}) {
    final serverUri = _normalizeServerUri(apiUrl);
    final dataSyncUri = _normalizeServerUri(powerSyncUrl);
    final server = CustomSyncServer(
      id: _customServerId(serverUri.toString()),
      url: serverUri.toString(),
      label: _labelForServerUri(serverUri),
      dataSyncUri: dataSyncUri,
      fileStorageQuotaBytes: null,
    );
    _saveCustomServers([server]);
    _setActiveServerId(server.id);
    notifyListeners();
  }

  void _migrateLegacyCustomServer() {
    if (customServers.isNotEmpty) return;

    final legacyApiUrl = _prefs.getString(_legacyKeyCustomApiUrl);
    final legacyDataSyncUrl = _prefs.getString(_legacyKeyCustomPowerSyncUrl);
    if (legacyApiUrl == null || legacyApiUrl.isEmpty || legacyDataSyncUrl == null || legacyDataSyncUrl.isEmpty) {
      return;
    }

    final serverUri = _normalizeServerUri(legacyApiUrl);
    final dataSyncUri = _normalizeServerUri(legacyDataSyncUrl);
    final server = CustomSyncServer(
      id: _customServerId(serverUri.toString()),
      url: serverUri.toString(),
      label: _labelForServerUri(serverUri),
      dataSyncUri: dataSyncUri,
      fileStorageQuotaBytes: null,
    );

    _saveCustomServers([server]);
    if (_prefs.getString(_legacyKeyServerType) == SyncServerType.custom.name) {
      _setActiveServerId(server.id);
    }
  }

  CustomSyncServer _customServerFromDiscovery(Uri serverUri, DataSyncDiscoverySettings settings) {
    final normalizedUrl = serverUri.toString();
    return CustomSyncServer(
      id: _customServerId(normalizedUrl),
      url: normalizedUrl,
      label: _labelForServerUri(serverUri),
      dataSyncUri: settings.dataSyncUri,
      fileStorageQuotaBytes: settings.fileStorageQuotaBytes,
    );
  }

  void _saveCustomServers(List<CustomSyncServer> servers) {
    _prefs.setString(_keyCustomServers, jsonEncode(servers.map((server) => server.toJson()).toList()));
  }

  void _setActiveServerId(String id) {
    _prefs.setString(_keyActiveServerId, id);
  }

  static Future<DataSyncDiscoverySettings> _fetchDataSyncSettings(Uri serverUrl) async {
    final client = http.Client();
    try {
      final config = PapyrusApiConfig(serverBaseUri: serverUrl);
      final response = await client.get(config.endpoint('/sync/settings'), headers: {'Accept': 'application/json'});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const SyncSettingsException('Server settings could not be loaded');
      }
      return DataSyncDiscoverySettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (error) {
      if (error is SyncSettingsException) rethrow;
      throw const SyncSettingsException('Server settings could not be loaded');
    } finally {
      client.close();
    }
  }

  Uri _normalizeServerUri(String value) {
    final trimmed = value.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SyncSettingsException('Expected a valid server URL');
    }

    final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: path, query: null, fragment: null);
  }

  String _customServerId(String normalizedUrl) {
    final digest = sha256.convert(utf8.encode(normalizedUrl)).toString();
    return 'custom-${digest.substring(0, 16)}';
  }

  String _labelForServerUri(Uri uri) {
    final path = uri.path.isEmpty ? '' : uri.path;
    return '${uri.authority}$path';
  }

  String _formatBytes(int bytes) {
    const mib = 1024 * 1024;
    const gib = 1024 * mib;

    if (bytes >= gib) return '${_formatByteValue(bytes / gib)} GB';
    if (bytes == 0) return '0 MB';
    return '${_formatByteValue(bytes / mib)} MB';
  }

  String _formatByteValue(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }
}
