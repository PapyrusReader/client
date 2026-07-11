import 'dart:async';

typedef SyncProfileSwitchErrorHandler = void Function(Object error, StackTrace stackTrace);

/// Serializes server-profile switches while retaining the latest user request.
class SyncProfileSwitchQueue {
  SyncProfileSwitchQueue({required String initialProfileKey, required SyncProfileSwitchErrorHandler onError})
    : _requestedProfileKey = initialProfileKey,
      _onError = onError;

  final SyncProfileSwitchErrorHandler _onError;
  String _requestedProfileKey;
  Future<void> _tail = Future<void>.value();

  String get requestedProfileKey => _requestedProfileKey;

  bool request(String profileKey, Future<void> Function() switchProfile) {
    if (profileKey == _requestedProfileKey) return false;
    _requestedProfileKey = profileKey;

    final operation = _tail.then((_) => switchProfile());
    _tail = operation.then<void>((_) {}, onError: _onError);
    return true;
  }

  Future<void> waitUntilIdle() => _tail;
}
