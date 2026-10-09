import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// An installation identity shared by reader, manual, and correction records.
abstract final class ReadingDeviceIdentity {
  static const preferenceKey = 'reading_device_id';
  static String _value = const Uuid().v4();

  static String get current => _value;

  static Future<void> initialize(SharedPreferences preferences) async {
    final stored = preferences.getString(preferenceKey);

    if (stored != null && stored.isNotEmpty) {
      _value = stored;
    } else {
      await preferences.setString(preferenceKey, _value);
    }
  }
}
