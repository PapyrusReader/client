import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncServerType { official, custom }

enum MediaStorageBackend { local, selfHosted }

class SyncSettingsProvider extends ChangeNotifier {
  static const _keyServerType = 'sync_server_type';
  static const _keyCustomApiUrl = 'sync_custom_api_url';
  static const _keyCustomPowerSyncUrl = 'sync_custom_powersync_url';
  static const _keyMediaStorageBackend = 'media_storage_backend';

  final SharedPreferences _prefs;
  final PapyrusApiConfig officialConfig;

  SyncSettingsProvider(this._prefs, {required this.officialConfig});

  SyncServerType get serverType {
    final value = _prefs.getString(_keyServerType);
    return value == SyncServerType.custom.name ? SyncServerType.custom : SyncServerType.official;
  }

  set serverType(SyncServerType value) {
    _prefs.setString(_keyServerType, value.name);
    if (value == SyncServerType.official && mediaStorageBackend != MediaStorageBackend.local) {
      _prefs.setString(_keyMediaStorageBackend, MediaStorageBackend.local.name);
    }
    notifyListeners();
  }

  String get customApiUrl => _prefs.getString(_keyCustomApiUrl) ?? '';

  String get customPowerSyncUrl => _prefs.getString(_keyCustomPowerSyncUrl) ?? '';

  void setCustomServerUrls({required String apiUrl, required String powerSyncUrl}) {
    final normalizedApiUrl = _normalizeUrl(apiUrl);
    final normalizedPowerSyncUrl = _normalizeUrl(powerSyncUrl);

    _prefs.setString(_keyCustomApiUrl, normalizedApiUrl);
    _prefs.setString(_keyCustomPowerSyncUrl, normalizedPowerSyncUrl);
    notifyListeners();
  }

  String get activeServerLabel {
    return serverType == SyncServerType.official ? 'Official server' : 'Custom server';
  }

  PapyrusApiConfig get activeApiConfig {
    if (serverType == SyncServerType.official) {
      return officialConfig;
    }

    return PapyrusApiConfig(serverBaseUri: Uri.parse(customApiUrl), powerSyncServiceUri: Uri.parse(customPowerSyncUrl));
  }

  String get activeProfileKey {
    if (serverType == SyncServerType.official) {
      return 'official';
    }

    final input = '${activeApiConfig.serverBaseUri}|${activeApiConfig.powerSyncServiceUri}';
    final digest = sha256.convert(utf8.encode(input)).toString();
    return 'custom-${digest.substring(0, 16)}';
  }

  MediaStorageBackend get mediaStorageBackend {
    final value = _prefs.getString(_keyMediaStorageBackend);
    final backend = value == MediaStorageBackend.selfHosted.name
        ? MediaStorageBackend.selfHosted
        : MediaStorageBackend.local;

    if (serverType == SyncServerType.official && backend != MediaStorageBackend.local) {
      return MediaStorageBackend.local;
    }

    return backend;
  }

  set mediaStorageBackend(MediaStorageBackend value) {
    if (serverType == SyncServerType.official && value != MediaStorageBackend.local) {
      _prefs.setString(_keyMediaStorageBackend, MediaStorageBackend.local.name);
      notifyListeners();
      return;
    }

    _prefs.setString(_keyMediaStorageBackend, value.name);
    notifyListeners();
  }

  String get mediaStorageLabel {
    switch (mediaStorageBackend) {
      case MediaStorageBackend.local:
        return 'Local device only';
      case MediaStorageBackend.selfHosted:
        return 'Self-hosted server';
    }
  }

  String? get mediaStorageRestrictionMessage {
    if (serverType == SyncServerType.official) {
      return 'Official servers do not store book files or covers. Media stays on this device.';
    }

    return null;
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Expected a valid server URL');
    }

    return uri.removeFragment().toString();
  }
}
