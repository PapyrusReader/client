import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accessibility defaults follow the system and changes survive reload', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = PreferencesProvider(storage);
    addTearDown(preferences.dispose);
    expect(preferences.interfaceTextEnlargement, 1);
    expect(preferences.increaseContrast, isFalse);
    expect(preferences.boldInterfaceText, isFalse);
    var notifications = 0;
    preferences.addListener(() => notifications++);
    preferences.interfaceTextEnlargement = 1.3;
    preferences.increaseContrast = true;
    preferences.boldInterfaceText = true;
    expect(notifications, 3);
    await storage.reload();
    final restored = PreferencesProvider(storage);
    addTearDown(restored.dispose);
    expect(restored.interfaceTextEnlargement, 1.3);
    expect(restored.increaseContrast, isTrue);
    expect(restored.boldInterfaceText, isTrue);
  });

  for (final value in [-1.0, 0.0, 1.2, 3.0, double.nan, double.infinity, 'large', 2]) {
    test('invalid saved text enlargement $value uses the system default', () async {
      SharedPreferences.setMockInitialValues({'interface_text_enlargement': value});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      addTearDown(preferences.dispose);
      expect(preferences.interfaceTextEnlargement, 1);
      preferences.interfaceTextEnlargement = 0.5;
      expect(preferences.interfaceTextEnlargement, 1);
    });
  }
}
