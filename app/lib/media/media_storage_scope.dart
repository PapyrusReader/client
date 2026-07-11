/// Identifies local authenticated media belonging to one server and user.
class MediaStorageScope {
  MediaStorageScope({required this.profileKey, required this.userId}) {
    if (!_safePart.hasMatch(profileKey) || !_safePart.hasMatch(userId)) {
      throw ArgumentError('Media storage scope contains unsafe characters');
    }
  }

  static final RegExp _safePart = RegExp(r'^[a-zA-Z0-9_.-]+$');

  final String profileKey;
  final String userId;

  String get persistenceKey => '$profileKey--$userId';

  @override
  bool operator ==(Object other) {
    return other is MediaStorageScope && other.profileKey == profileKey && other.userId == userId;
  }

  @override
  int get hashCode => Object.hash(profileKey, userId);
}
