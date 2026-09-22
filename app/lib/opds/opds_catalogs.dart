import 'package:flutter/foundation.dart';
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_library.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';

class OpdsCatalogs extends ChangeNotifier {
  OpdsCatalogs(this.store, {this.library, this.cache});
  final OpdsCatalogStore store;
  final OpdsLibrary? library;
  final OpdsResourceCache? cache;
  String? _scope;
  String? get scope => _scope;
  int revision = 0;
  List<OpdsCatalog> catalogs = const [];
  String? error;
  bool _disposed = false;
  OpdsCatalog? find(String id) {
    for (final catalog in catalogs) {
      if (catalog.id == id) return catalog;
    }
    return null;
  }

  void setScope(String? scope) {
    if (_scope == scope) return;
    _scope = scope;
    library?.setScope(scope);
    cache?.setScope(scope);
    reload();
  }

  void reload() {
    revision++;
    error = null;
    try {
      catalogs = _scope == null ? const [] : List.unmodifiable(store.load(_scope!));
    } catch (failure) {
      catalogs = const [];
      error = opdsErrorMessage(failure);
    }
    if (!_disposed) notifyListeners();
  }

  Future<OpdsCredentials?> credentials(String id) async {
    final scope = _scope;
    if (scope == null) throw const OpdsException('Wait for the library account to finish loading.');
    final catalog = find(id);
    final currentRevision = revision;
    if (catalog == null) throw const OpdsCancelled();
    final credentials = await store.credentials(scope, id, expectedOrigin: catalog.uri.origin);
    if (_scope != scope || revision != currentRevision || _disposed) throw const OpdsCancelled();
    return credentials;
  }

  Future<void> save(OpdsCatalog catalog, {OpdsCredentials? credentials, bool clearCredentials = false}) async {
    final scope = _scope;
    if (scope == null) throw const OpdsException('Wait for the library account to finish loading.');
    final previous = find(catalog.id);
    await store.save(scope, catalog, credentials: credentials, clearCredentials: clearCredentials);
    if (previous != null && (previous.uri != catalog.uri || credentials != null || clearCredentials)) {
      await cache?.invalidateCatalog(previous, scope: scope);
      await library?.forgetCatalog(previous.id, scope: scope);
    }
    if (_scope == scope && !_disposed) reload();
  }

  Future<void> remove(String id) async {
    final scope = _scope;
    if (scope == null) return;
    final catalog = find(id);
    await store.remove(scope, id);
    if (catalog != null) {
      await cache?.invalidateCatalog(catalog, scope: scope);
      await library?.forgetCatalog(id, scope: scope);
    }
    if (_scope == scope && !_disposed) reload();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
