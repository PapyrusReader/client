import 'dart:convert';

class UploadCooldowns {
  static final shared = UploadCooldowns();

  final Map<(Uri, String), DateTime> _retryAt = {};

  Duration? remaining(Uri endpoint, String accessToken, DateTime now) {
    _retryAt.removeWhere((_, retryAt) => !retryAt.isAfter(now));
    return _retryAt[(endpoint, _accountKey(accessToken))]?.difference(now);
  }

  void deferUntil(Uri endpoint, String accessToken, DateTime retryAt) {
    final key = (endpoint, _accountKey(accessToken));
    final existing = _retryAt[key];

    if (existing == null || retryAt.isAfter(existing)) {
      _retryAt[key] = retryAt;
    }
  }

  String _accountKey(String accessToken) {
    // The subject groups local retry hints only. The server validates authentication.
    final parts = accessToken.split('.');

    if (parts.length == 3) {
      try {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));

        if (payload is Map<String, dynamic>) {
          final subject = payload['sub'];

          if (subject is String && subject.isNotEmpty) {
            return 'user:$subject';
          }
        }
      } on FormatException {
        return 'token:$accessToken';
      }
    }

    return 'token:$accessToken';
  }
}
