import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A request snapshot; callers must capture it before starting network work.
class OpdsCacheToken {
  OpdsCacheToken._(this._owner, this._scope, this._catalogId, this._root, this._uri, this._epoch, this._generation);
  final OpdsResourceCache _owner;
  final String _scope;
  final String _catalogId;
  final String _root;
  final String _uri;
  final int _epoch;
  final int _generation;
  String get _catalogKey => jsonEncode([_scope, _catalogId]);
  String get _key => jsonEncode([_scope, _catalogId, _root, _uri]);
}

class OpdsCachedResource {
  const OpdsCachedResource({required this.response, required this.fetchedAt});
  final OpdsResponse response;
  final DateTime fetchedAt;
}

/// One bounded payload for every account, catalog, feed and thumbnail.
/// Only response bytes, the final URL and content type are retained.
class OpdsResourceCache extends ChangeNotifier {
  OpdsResourceCache(
    this._prefs, {
    this.maxBytes = 2 * 1024 * 1024,
    this.maxEntryBytes = 512 * 1024,
    this.maxEntries = 64,
  }) {
    _restore();
  }

  static const _storageKey = 'papyrus.opds.resources.v1';
  final SharedPreferences _prefs;
  final int maxBytes;
  final int maxEntryBytes;
  final int maxEntries;
  final _entries = <String, Map<String, dynamic>>{};
  final _generations = <String, int>{};
  Future<void> _pending = Future.value();
  String? _scope;
  int _epoch = 0;

  void setScope(String? scope) {
    if (_scope == scope) return;
    _scope = scope;
    _epoch++;
    notifyListeners();
  }

  OpdsCacheToken? capture(OpdsCatalog catalog, Uri uri) {
    final scope = _scope;
    if (scope == null) return null;
    OpdsHttpClient.validateUri(catalog.uri);
    OpdsHttpClient.validateUri(uri);
    final catalogKey = jsonEncode([scope, catalog.id]);
    return OpdsCacheToken._(
      this,
      scope,
      catalog.id,
      catalog.uri.toString(),
      uri.toString(),
      _epoch,
      _generations[catalogKey] ?? 0,
    );
  }

  bool isCurrent(OpdsCacheToken token) =>
      identical(token._owner, this) &&
      token._scope == _scope &&
      token._epoch == _epoch &&
      token._generation == (_generations[token._catalogKey] ?? 0);

  OpdsCachedResource? read(OpdsCacheToken token) {
    if (!isCurrent(token)) return null;
    final entry = _entries.remove(token._key);
    if (entry == null) return null;
    try {
      final resource = _decode(entry);
      _entries[token._key] = entry;
      return resource;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(OpdsCacheToken token, OpdsResponse response) {
    if (!isCurrent(token) || response.bytes.length > maxEntryBytes || maxEntries <= 0) return Future.value();
    try {
      OpdsHttpClient.validateUri(response.uri);
      final entry = <String, dynamic>{
        'key': token._key,
        'uri': response.uri.toString(),
        'type': response.headers['content-type'],
        'bytes': base64Encode(response.bytes),
        'at': DateTime.now().toUtc().millisecondsSinceEpoch,
      };
      if (utf8.encode(jsonEncode(entry)).length > maxEntryBytes) return Future.value();
      _entries.remove(token._key);
      _entries[token._key] = entry;
      _trim();
      return _persist();
    } catch (_) {
      return Future.value();
    }
  }

  Future<void> remove(OpdsCacheToken token) {
    if (!isCurrent(token)) return Future.value();
    _entries.remove(token._key);
    return _persist();
  }

  Future<void> invalidateCatalog(OpdsCatalog catalog, {String? scope}) {
    scope ??= _scope;
    if (scope == null) return Future.value();
    final catalogKey = jsonEncode([scope, catalog.id]);
    _generations[catalogKey] = (_generations[catalogKey] ?? 0) + 1;
    _entries.removeWhere((key, _) {
      final parts = jsonDecode(key) as List;
      return parts[0] == scope && parts[1] == catalog.id;
    });
    notifyListeners();
    return _persist();
  }

  String _serialize() => jsonEncode({'version': 1, 'entries': _entries.values.toList()});

  void _trim() {
    while (_entries.isNotEmpty && (_entries.length > maxEntries || utf8.encode(_serialize()).length > maxBytes)) {
      _entries.remove(_entries.keys.first);
    }
  }

  OpdsCachedResource _decode(Map<String, dynamic> entry) {
    final parts = jsonDecode(entry['key'] as String) as List;
    if (parts.length != 4 || parts.any((part) => part is! String)) throw const FormatException('Invalid cache key');
    OpdsHttpClient.validateUri(Uri.parse(parts[2] as String));
    OpdsHttpClient.validateUri(Uri.parse(parts[3] as String));
    final bytes = base64Decode(entry['bytes'] as String);
    if (bytes.length > maxEntryBytes) throw const FormatException('Oversized cache entry');
    return OpdsCachedResource(
      response: OpdsResponse(
        uri: OpdsHttpClient.validateUri(Uri.parse(entry['uri'] as String)),
        bytes: bytes,
        headers: {if (entry['type'] != null) 'content-type': entry['type'] as String},
      ),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(entry['at'] as int, isUtc: true),
    );
  }

  void _restore() {
    try {
      final raw = _prefs.getString(_storageKey);
      if (raw == null || utf8.encode(raw).length > maxBytes) return;
      final payload = jsonDecode(raw) as Map;
      if (payload['version'] != 1) return;
      for (final rawEntry in payload['entries'] as List) {
        try {
          final entry = Map<String, dynamic>.from(rawEntry as Map);
          if (utf8.encode(jsonEncode(entry)).length > maxEntryBytes) continue;
          _decode(entry);
          _entries[entry['key'] as String] = entry;
        } catch (_) {
          // One damaged entry does not discard other catalogs.
        }
      }
      _trim();
    } catch (_) {
      _entries.clear();
    }
  }

  Future<void> _persist() {
    // Serialize writes so an older save cannot resurrect invalidated data.
    _pending = _pending.then((_) async {
      try {
        final payload = _serialize();
        if (_entries.isEmpty || utf8.encode(payload).length > maxBytes) {
          await _prefs.remove(_storageKey);
        } else {
          final saved = await _prefs.setString(_storageKey, payload);
          if (!saved) await _prefs.remove(_storageKey);
        }
      } catch (_) {
        // Prefer a missing disk cache to old protected data after invalidation.
        try {
          await _prefs.remove(_storageKey);
        } catch (_) {
          // Quota and storage failures never block catalog browsing.
        }
      }
    });
    return _pending;
  }
}
