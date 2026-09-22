import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captured before import, so its result cannot be attributed to another account.
class OpdsImportIdentity {
  const OpdsImportIdentity(this.scope, this.generation, this.parts, this.sample);
  final String scope;
  final int generation;
  final List<String> parts;
  final bool sample;
}

/// Local provenance, separate from catalog metadata and the library's book model.
class OpdsLibrary extends ChangeNotifier {
  OpdsLibrary(this._prefs, {required DataStore dataStore}) : _dataStore = dataStore {
    _dataStore.addListener(_changed);
  }

  final SharedPreferences _prefs;
  final DataStore _dataStore;
  Map<String, Map<String, dynamic>> _imports = {};
  final Map<String, Map<String, Map<String, dynamic>>> _scopedImports = {};
  String? _scope;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  String _key(String scope) => 'papyrus.opds.imports.v1.${Uri.encodeComponent(scope)}';

  void setScope(String? scope) {
    if (_scope == scope) return;
    _scope = scope;
    _generation++;
    _imports = scope == null ? {} : _scopedImports.putIfAbsent(scope, () => _read(scope));
    _changed();
  }

  Map<String, Map<String, dynamic>> _read(String scope) {
    final imports = <String, Map<String, dynamic>>{};
    try {
      final raw = _prefs.getString(_key(scope));
      if (raw == null) return imports;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        try {
          final parts = jsonDecode(entry.key);
          if (parts is! List || parts.length != 4 || parts.any((part) => part is! String)) continue;
          final value = Map<String, dynamic>.from(entry.value as Map);
          if (value['book'] is String && value['sample'] is bool) imports[entry.key] = value;
        } catch (_) {
          // Ignore a damaged record without losing unrelated import identities.
        }
      }
    } catch (_) {
      // Broken optional provenance must not prevent opening the library.
    }
    return imports;
  }

  OpdsImportIdentity? capture(OpdsCatalog catalog, OpdsPublication publication, OpdsLink link) {
    final scope = _scope;
    if (scope == null || publication.id.isEmpty) return null;
    return OpdsImportIdentity(scope, _generation, [
      catalog.id,
      catalog.uri.toString(),
      publication.id,
      '${link.uri}',
    ], link.hasRel('preview') || link.hasRel('http://opds-spec.org/acquisition/sample'));
  }

  String? bookId(OpdsCatalog catalog, OpdsPublication publication, {OpdsLink? link}) {
    if (_scope == null || !_dataStore.isLoaded || publication.id.isEmpty) return null;
    for (final entry in _imports.entries) {
      final parts = (jsonDecode(entry.key) as List).cast<String>();
      if (parts.length != 4 || parts[0] != catalog.id || parts[1] != '${catalog.uri}' || parts[2] != publication.id) {
        continue;
      }
      if (link != null ? parts[3] != '${link.uri}' : entry.value['sample'] == true) continue;
      final id = entry.value['book'] as String;
      if (_dataStore.getBook(id) != null) return id;
    }
    return null;
  }

  Future<void> record(OpdsImportIdentity identity, String bookId) async {
    if (_disposed || identity.scope != _scope || identity.generation != _generation) return;
    _imports[jsonEncode(identity.parts)] = {'book': bookId, 'sample': identity.sample};
    _changed();
    await _persist(identity.scope, _imports);
  }

  /// Credentials or the source URL changed: identifiers may now mean other books.
  Future<void> forgetCatalog(String catalogId, {required String scope}) async {
    final imports = _scopedImports.putIfAbsent(scope, () => _read(scope));
    imports.removeWhere((key, _) => (jsonDecode(key) as List).first == catalogId);
    if (_scope == scope) _generation++;
    _changed();
    await _persist(scope, imports);
  }

  Future<void> _persist(String scope, Map<String, Map<String, dynamic>> imports) {
    final json = jsonEncode(imports);
    // Serialize snapshots, including when an older scope's write is still pending.
    _pending = _pending.then((_) async {
      try {
        await _prefs.setString(_key(scope), json);
      } catch (_) {
        // The imported book remains valid even if optional local metadata cannot save.
      }
    });
    return _pending;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _dataStore.removeListener(_changed);
    super.dispose();
  }
}
