class PapyrusApiConfig {
  static const _defaultBaseUrl = 'http://localhost:8080';

  final Uri serverBaseUri;
  final String apiPrefix;

  const PapyrusApiConfig({required this.serverBaseUri, this.apiPrefix = '/v1'});

  factory PapyrusApiConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('PAPYRUS_API_BASE_URL', defaultValue: _defaultBaseUrl);

    return PapyrusApiConfig(serverBaseUri: Uri.parse(rawBaseUrl));
  }

  Uri get apiBaseUri {
    final normalizedPrefix = apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix';
    return serverBaseUri.replace(path: normalizedPrefix);
  }

  Uri endpoint(String path, [Map<String, String>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final apiPath = '${apiBaseUri.path}$normalizedPath';

    return apiBaseUri.replace(path: apiPath, queryParameters: queryParameters);
  }
}
