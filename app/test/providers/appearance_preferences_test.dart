import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('page alignment defaults left and both choices survive storage reload', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = PreferencesProvider(storage);
    addTearDown(preferences.dispose);
    expect(preferences.pageAlignment, 'left');
    var notifications = 0;
    preferences.addListener(() => notifications++);

    for (final alignment in ['center', 'left']) {
      preferences.pageAlignment = alignment;
      await storage.reload();
      final restored = PreferencesProvider(storage);
      expect(restored.pageAlignment, alignment);
      restored.dispose();
    }

    expect(notifications, 2);
  });

  for (final value in ['invalid', true, 1]) {
    test('invalid saved page alignment $value uses left', () async {
      SharedPreferences.setMockInitialValues({'page_alignment': value});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      addTearDown(preferences.dispose);
      expect(preferences.pageAlignment, 'left');
    });
  }
}
