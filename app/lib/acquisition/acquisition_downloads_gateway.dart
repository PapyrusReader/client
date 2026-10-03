import 'package:papyrus/acquisition/acquisition_api_client.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/providers/auth_provider.dart';

class AcquisitionSubmissionOutcome {
  final int successfulCount;
  final Map<String, String> failuresByReleaseToken;

  AcquisitionSubmissionOutcome({required this.successfulCount, required Map<String, String> failuresByReleaseToken})
    : failuresByReleaseToken = Map.unmodifiable(failuresByReleaseToken);

  int get failedCount => failuresByReleaseToken.length;

  bool get allSucceeded => failedCount == 0 && successfulCount > 0;
}

class AcquisitionJobFilesResult {
  AcquisitionJobFilesResult.success(List<AcquisitionFileCandidate> files)
    : files = List.unmodifiable(files),
      error = null;

  const AcquisitionJobFilesResult.failure(String message) : files = const [], error = message;

  final List<AcquisitionFileCandidate> files;
  final String? error;

  bool get isSuccess => error == null;
}

class AcquisitionJobActionOutcome {
  const AcquisitionJobActionOutcome.success() : error = null, ignored = false;

  const AcquisitionJobActionOutcome.failure(this.error) : ignored = false;

  const AcquisitionJobActionOutcome.ignored() : error = null, ignored = true;

  final String? error;
  final bool ignored;

  bool get succeeded => !ignored && error == null;

  bool get failed => error != null;
}

abstract interface class AcquisitionDownloadsGateway {
  Future<List<AcquisitionEndpoint>> listEndpoints();

  Future<AcquisitionJobPage> listJobs({int limit = 50, int offset = 0});

  Future<List<TorrentRelease>> search(String query, {List<String>? endpointIds});

  Future<BatchSubmissionResponse> submitReleaseBatch({
    required String endpointId,
    required List<TorrentRelease> releases,
  });

  Future<List<AcquisitionFileCandidate>> listJobFiles(String jobId);

  Future<AcquisitionJob> selectJobFile(String jobId, int fileIndex);

  Future<AcquisitionJob> cancelJob(String jobId);

  Future<AcquisitionJob> retryJobImport(String jobId);

  Future<void> removeJob(String jobId);

  void close();
}

class AuthenticatedAcquisitionDownloadsGateway implements AcquisitionDownloadsGateway {
  final AuthProvider _authProvider;
  final AcquisitionApiClient _apiClient;

  AuthenticatedAcquisitionDownloadsGateway({
    required AuthProvider authProvider,
    required AcquisitionApiClient apiClient,
  }) : _authProvider = authProvider,
       _apiClient = apiClient;

  @override
  Future<List<AcquisitionEndpoint>> listEndpoints() {
    return _authProvider.withFreshAccessToken(_apiClient.listEndpoints);
  }

  @override
  Future<AcquisitionJobPage> listJobs({int limit = 50, int offset = 0}) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.listJobs(accessToken: accessToken, limit: limit, offset: offset),
    );
  }

  @override
  Future<List<TorrentRelease>> search(String query, {List<String>? endpointIds}) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.search(accessToken: accessToken, query: query, endpointIds: endpointIds),
    );
  }

  @override
  Future<BatchSubmissionResponse> submitReleaseBatch({
    required String endpointId,
    required List<TorrentRelease> releases,
  }) {
    return _authProvider.withFreshAccessToken(
      (accessToken) =>
          _apiClient.submitReleaseBatch(accessToken: accessToken, endpointId: endpointId, releases: releases),
    );
  }

  @override
  Future<List<AcquisitionFileCandidate>> listJobFiles(String jobId) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.listJobFiles(accessToken: accessToken, jobId: jobId),
    );
  }

  @override
  Future<AcquisitionJob> selectJobFile(String jobId, int fileIndex) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.selectJobFile(accessToken: accessToken, jobId: jobId, fileIndex: fileIndex),
    );
  }

  @override
  Future<AcquisitionJob> cancelJob(String jobId) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.cancelJob(accessToken: accessToken, jobId: jobId),
    );
  }

  @override
  Future<AcquisitionJob> retryJobImport(String jobId) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.retryJobImport(accessToken: accessToken, jobId: jobId),
    );
  }

  @override
  Future<void> removeJob(String jobId) {
    return _authProvider.withFreshAccessToken(
      (accessToken) => _apiClient.removeJob(accessToken: accessToken, jobId: jobId),
    );
  }

  @override
  void close() {
    _apiClient.close();
  }
}
