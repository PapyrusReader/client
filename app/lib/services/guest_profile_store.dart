import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the local account separate from every signed-in account and server.
class GuestProfileStore {
  static const preferenceKey = 'guest_profile';
  static const defaultDisplayName = 'Anonymous User';

  final SharedPreferences _prefs;
  String _displayName = defaultDisplayName;
  Uint8List? _photoBytes;

  String get displayName => _displayName;
  Uint8List? get photoBytes => _photoBytes;

  GuestProfileStore(this._prefs) {
    final saved = _prefs.get(preferenceKey);

    if (saved is! String) {
      return;
    }

    try {
      final profile = jsonDecode(saved) as Map<String, dynamic>;
      final name = profile['display_name'] as String;
      final photo = profile['photo'] as String?;

      if (name.trim().isEmpty || name.length > 100) {
        return;
      }

      _photoBytes = photo == null ? null : base64Decode(photo);
      _displayName = name;
    } catch (_) {
      _displayName = defaultDisplayName;
      _photoBytes = null;
    }
  }

  Future<void> save({required String displayName, Uint8List? photoBytes}) async {
    // Flutter's web image decoder requires a native typed buffer, not an unmodifiable view.
    final photo = photoBytes == null ? _photoBytes : Uint8List.fromList(photoBytes);
    final record = jsonEncode({
      'display_name': displayName,
      'photo': photo == null ? null : base64Encode(photo),
    });

    if (!await _prefs.setString(preferenceKey, record)) {
      throw StateError('Could not save the local profile.');
    }

    _displayName = displayName;
    _photoBytes = photo;
  }

  Future<void> clear() async {
    if (!await _prefs.remove(preferenceKey)) {
      throw StateError('Could not clear the local profile.');
    }

    _displayName = defaultDisplayName;
    _photoBytes = null;
  }
}
