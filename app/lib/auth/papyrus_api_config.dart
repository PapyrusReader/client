class PapyrusApiConfig {
  static const _defaultBaseUrl = 'http://localhost:8080';
  static const _defaultPowerSyncServiceUrl = 'http://localhost:8081';

  final Uri serverBaseUri;
  final Uri powerSyncServiceUri;
  final String apiPrefix;

  PapyrusApiConfig({required this.serverBaseUri, Uri? powerSyncServiceUri, this.apiPrefix = '/v1'})
    : powerSyncServiceUri = powerSyncServiceUri ?? Uri.parse(_defaultPowerSyncServiceUrl);

  factory PapyrusApiConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('PAPYRUS_API_BASE_URL', defaultValue: _defaultBaseUrl);
    const rawPowerSyncServiceUrl = String.fromEnvironment(
      'POWERSYNC_SERVICE_URL',
      defaultValue: _defaultPowerSyncServiceUrl,
    );

    return PapyrusApiConfig(
      serverBaseUri: Uri.parse(rawBaseUrl),
      powerSyncServiceUri: Uri.parse(rawPowerSyncServiceUrl),
    );
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
