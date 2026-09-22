import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_parser.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:papyrus/opds/opds_search.dart';

class OpdsBrowser extends ChangeNotifier {
  OpdsBrowser({OpdsHttpClient? httpClient}) : httpClient = httpClient ?? OpdsHttpClient() {
    this.httpClient.cache?.addListener(_cacheChanged);
  }
  final OpdsHttpClient httpClient;
  OpdsFeed? feed;
  String? error;
  bool loading = false;
  bool isCached = false;
  bool authorizationFailed = false;
  bool cacheInvalidated = false;
  DateTime? fetchedAt;
  OpdsCatalog? _catalog;
  OpdsCredentials? _credentials;
  OpdsCancellation _cancellation = OpdsCancellation();
  OpdsCacheToken? _activeCacheToken;
  bool _invalidatingAuthorization = false;
  bool _disposed = false;

  void _cacheChanged() {
    final token = _activeCacheToken;
    if (_disposed || token == null || httpClient.cache!.isCurrent(token)) return;
    _activeCacheToken = null;
    if (!_invalidatingAuthorization) _cancellation.cancel();
    feed = null;
    isCached = false;
    fetchedAt = null;
    cacheInvalidated = true;
    loading = false;
    error = 'Catalog data changed. Refresh to load it again.';
    _notify();
  }

  OpdsFeed _parse(OpdsResponse response) =>
      OpdsParser.parse(response.text, response.uri, contentType: response.headers['content-type']);

  void _checkRequest(OpdsCancellation token, OpdsCacheToken? cacheToken) {
    token.check();
    if (_disposed || (cacheToken != null && !httpClient.cache!.isCurrent(cacheToken))) {
      throw const OpdsCancelled();
    }
  }

  Future<T> _fetch<T>(
    OpdsCatalog catalog,
    Uri uri,
    OpdsCancellation token,
    OpdsCredentials? credentials,
    T Function(OpdsResponse) parse, {
    OpdsCacheToken? cacheToken,
    bool preferCached = false,
  }) async {
    final cache = httpClient.cache;
    cacheToken ??= cache?.capture(catalog, uri);
    _checkRequest(token, cacheToken);
    if (preferCached && cacheToken != null) {
      final cached = cache!.read(cacheToken);
      if (cached != null) {
        try {
          return parse(cached.response);
        } catch (_) {
          unawaited(cache.remove(cacheToken));
        }
      }
    }
    try {
      final response = await httpClient.get(catalog, uri, credentials: credentials, cancellation: token);
      _checkRequest(token, cacheToken);
      final parsed = parse(response);
      if (cacheToken != null) await cache!.write(cacheToken, response);
      _checkRequest(token, cacheToken);
      return parsed;
    } on OpdsAuthorizationException {
      _checkRequest(token, cacheToken);
      if (cacheToken != null) {
        // Other browsers cancel immediately; this request still reports its
        // authorization error after the synchronous invalidation notification.
        late Future<void> invalidating;
        _invalidatingAuthorization = true;
        try {
          invalidating = cache!.invalidateCatalog(catalog);
        } finally {
          _invalidatingAuthorization = false;
        }
        await invalidating;
      }
      rethrow;
    }
  }

  Future<void> load(OpdsCatalog catalog, Uri uri, {OpdsCredentials? credentials}) async {
    _cancellation.cancel();
    final token = _cancellation = OpdsCancellation();
    _catalog = catalog;
    _credentials = credentials;
    feed = null;
    error = null;
    isCached = false;
    authorizationFailed = false;
    cacheInvalidated = false;
    fetchedAt = null;
    final cache = httpClient.cache;
    final cacheToken = cache?.capture(catalog, uri);
    _activeCacheToken = cacheToken;
    if (cacheToken != null) {
      final cached = cache!.read(cacheToken);
      if (cached != null) {
        try {
          feed = _parse(cached.response);
          fetchedAt = cached.fetchedAt;
          isCached = true;
        } catch (_) {
          unawaited(cache.remove(cacheToken));
        }
      }
    }
    loading = true;
    _notify();
    try {
      final loaded = await _fetch(catalog, uri, token, credentials, _parse, cacheToken: cacheToken);
      if (token.isCancelled || _disposed) return;
      feed = loaded;
      isCached = false;
      fetchedAt = cacheToken == null ? DateTime.now() : cache!.read(cacheToken)?.fetchedAt ?? DateTime.now();
    } on OpdsCancelled {
      return;
    } catch (failure) {
      if (token.isCancelled || _disposed) return;
      if (failure is OpdsAuthorizationException) {
        feed = null;
        isCached = false;
        fetchedAt = null;
        authorizationFailed = true;
      }
      error = opdsErrorMessage(failure);
    } finally {
      if (!token.isCancelled && !_disposed) {
        if (cacheToken != null && !cache!.isCurrent(cacheToken)) {
          feed = null;
          isCached = false;
          fetchedAt = null;
        }
        loading = false;
        _notify();
      }
    }
  }

  Future<Uri> search(String query) async {
    final catalog = _catalog;
    if (catalog == null || query.trim().isEmpty) throw const OpdsException('Enter a search term.');
    final token = _cancellation;
    final cacheToken = httpClient.cache?.capture(catalog, catalog.uri);
    try {
      var link = feed?.searchLink;
      link ??= (await _fetch(catalog, catalog.uri, token, _credentials, _parse, preferCached: true)).searchLink;
      _checkRequest(token, cacheToken);
      if (link == null) throw const OpdsException('This catalog does not advertise keyword search.');
      if (link.type?.split(';').first.trim().toLowerCase() == 'application/opensearchdescription+xml') {
        link = await _fetch(
          catalog,
          link.uri,
          token,
          _credentials,
          (response) => OpdsSearch.fromOpenSearch(response.text, response.uri),
          preferCached: true,
        );
      }
      _checkRequest(token, cacheToken);
      return OpdsHttpClient.validateUri(Uri.parse(OpdsSearch.expand(link.template, query.trim())));
    } on OpdsAuthorizationException catch (failure) {
      if (!token.isCancelled && !_disposed) {
        feed = null;
        isCached = false;
        fetchedAt = null;
        authorizationFailed = true;
        error = failure.message;
        _notify();
      }
      rethrow;
    }
  }

  void clear() {
    _cancellation.cancel();
    _catalog = null;
    _credentials = null;
    feed = null;
    error = null;
    loading = false;
    isCached = false;
    authorizationFailed = false;
    cacheInvalidated = false;
    fetchedAt = null;
    _activeCacheToken = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    httpClient.cache?.removeListener(_cacheChanged);
    clear();
    super.dispose();
  }
}

String opdsErrorMessage(Object error) {
  if (error is OpdsException) return error.message;
  if (error is FormatException) return 'This response is not a supported OPDS catalog. Check the catalog URL.';
  return 'Could not load this catalog. Check its settings and retry.';
}
