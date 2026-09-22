import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';

class OpdsException implements Exception {
  const OpdsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OpdsCancelled extends OpdsException {
  const OpdsCancelled() : super('Download cancelled.');
}

class OpdsAuthorizationException extends OpdsException {
  const OpdsAuthorizationException(super.message);
}

class _OpdsRelayBusy extends OpdsException {
  const _OpdsRelayBusy(super.message);
}

/// Connection failures refer to the selected Papyrus relay server.
class OpdsConnectionException extends OpdsException {
  const OpdsConnectionException()
    : super(
        'Could not reach the Papyrus catalog server or the download was interrupted. Check your connection and retry.',
      );
}

class OpdsCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const OpdsCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

class OpdsResponse {
  const OpdsResponse({required this.uri, required this.bytes, required this.headers});
  final Uri uri;
  final Uint8List bytes;
  final Map<String, String> headers;
  String get text => utf8.decode(bytes);
}

/// Relays every resource through the backend without Papyrus bearer tokens.
class OpdsHttpClient {
  OpdsHttpClient({http.Client Function()? clientFactory, PapyrusApiConfig Function()? apiConfig, this.cache})
    : _clientFactory = clientFactory ?? http.Client.new,
      _apiConfig = apiConfig ?? PapyrusApiConfig.fromEnvironment;
  final http.Client Function() _clientFactory;
  final PapyrusApiConfig Function() _apiConfig;
  final OpdsResourceCache? cache;
  final _waitingRequests = Queue<Completer<void>>();
  int _activeRequests = 0;

  Future<void> _acquire(OpdsCancellation? cancellation) async {
    cancellation?.check();
    if (_activeRequests < 4) {
      _activeRequests++;
      return;
    }
    final pending = Completer<void>();
    _waitingRequests.add(pending);
    void cancel() {
      if (_waitingRequests.remove(pending)) pending.completeError(const OpdsCancelled());
    }

    cancellation?.addListener(cancel);
    try {
      await pending.future;
    } finally {
      cancellation?.removeListener(cancel);
    }
  }

  void _release() {
    if (_waitingRequests.isNotEmpty) {
      _waitingRequests.removeFirst().complete();
    } else {
      _activeRequests--;
    }
  }

  static Uri validateUri(Uri uri) {
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const OpdsException('Enter an HTTP or HTTPS URL without embedded credentials.');
    }
    return uri;
  }

  Future<OpdsResponse> get(
    OpdsCatalog catalog,
    Uri uri, {
    OpdsCredentials? credentials,
    OpdsCancellation? cancellation,
    void Function(int received, int? total)? onProgress,
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    validateUri(catalog.uri);
    validateUri(uri);
    cancellation?.check();
    final relayUri = validateUri(_apiConfig().endpoint('/opds/relay'));
    await _acquire(cancellation);
    http.Client? client;
    try {
      cancellation?.check();
      client = _clientFactory();
      cancellation?.addListener(client.close);
      late http.StreamedResponse response;
      final body = jsonEncode({
        'url': uri.toString(),
        'catalog_url': catalog.uri.toString(),
        'max_bytes': maxBytes,
        if (credentials != null) 'credentials': {'username': credentials.username, 'password': credentials.password},
      });
      for (var attempt = 0; ; attempt++) {
        cancellation?.check();
        final request = http.Request('POST', relayUri)
          ..headers['content-type'] = 'application/json'
          ..body = body;
        response = await client.send(request).timeout(const Duration(seconds: 35));
        if (response.statusCode == 200) break;
        final error = await _relayError(response);
        if (error is! _OpdsRelayBusy || attempt >= 2) throw error;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
      final upstreamUrl = response.headers['x-opds-url'];
      if (upstreamUrl == null) {
        throw const OpdsException(
          'The Papyrus server returned an invalid catalog response. Check its relay configuration.',
        );
      }
      final finalUri = validateUri(Uri.parse(upstreamUrl));
      final total = response.contentLength;
      if (total != null && total > maxBytes) throw const OpdsException('This resource is too large to load.');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(const Duration(seconds: 35))) {
        cancellation?.check();
        if (bytes.length + chunk.length > maxBytes) throw const OpdsException('This resource is too large to load.');
        bytes.add(chunk);
        onProgress?.call(bytes.length, total);
      }
      cancellation?.check();
      if (total != null && bytes.length != total) throw const OpdsConnectionException();
      return OpdsResponse(uri: finalUri, bytes: bytes.takeBytes(), headers: response.headers);
    } on OpdsException {
      rethrow;
    } catch (_) {
      cancellation?.check();
      throw const OpdsConnectionException();
    } finally {
      if (client != null) {
        cancellation?.removeListener(client.close);
        client.close();
      }
      _release();
    }
  }

  Future<OpdsException> _relayError(http.StreamedResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(const Duration(seconds: 35))) {
      if (bytes.length + chunk.length > 8192) break;
      bytes.add(chunk);
    }
    try {
      final body = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (body is Map && body['error'] is Map) {
        final error = body['error'] as Map;
        if (error['code'] == 'OPDS_RELAY_ERROR' && error['message'] is String) {
          if (response.statusCode == 503 && error['details'] is Map && error['details']['retryable'] == true) {
            return _OpdsRelayBusy(error['message'] as String);
          }
          return response.statusCode == 401 || response.statusCode == 403
              ? OpdsAuthorizationException(error['message'] as String)
              : OpdsException(error['message'] as String);
        }
      }
    } on FormatException {
      // Gateways can return HTML instead of the API error envelope.
    }
    final message = switch (response.statusCode) {
      401 => 'Check the catalog credentials and the Papyrus server relay configuration.',
      403 => 'The catalog or Papyrus server denied access. Check the catalog settings.',
      404 => 'The catalog resource or server relay was not found. Check the URL and update your Papyrus server.',
      413 => 'This resource is too large to load.',
      429 => 'Too many catalog requests. Please wait and retry.',
      _ => 'The catalog relay returned HTTP ${response.statusCode}. Please retry later.',
    };
    return response.statusCode == 401 || response.statusCode == 403
        ? OpdsAuthorizationException(message)
        : OpdsException(message);
  }
}
