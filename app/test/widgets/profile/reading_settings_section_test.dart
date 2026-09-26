import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/profile/reading_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ReadingSettingsSection', () {
    late PreferencesProvider prefsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'default_font': 'Georgia',
        'line_spacing': 'normal',
        'reading_mode': 'paginated',
        'page_turn_animation': true,
      });
      final prefs = await SharedPreferences.getInstance();
      prefsProvider = PreferencesProvider(prefs);
    });

    Widget buildSection({bool isDesktop = false}) {
      return ChangeNotifierProvider<PreferencesProvider>.value(
        value: prefsProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ReadingSettingsSection(isDesktop: isDesktop)),
          ),
        ),
      );
    }

    testWidgets('renders mobile reading options and allows toggling page animation', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: false));

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Default font'), findsOneWidget);
      expect(find.text('Line spacing'), findsOneWidget);
      expect(find.text('Reading mode'), findsOneWidget);
      expect(find.text('Page turn animation'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(prefsProvider.pageTurnAnimation, isFalse);
    });

    testWidgets('renders desktop reading typography and behavior options', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: true));

      expect(find.text('Typography'), findsOneWidget);
      expect(find.text('Default font size'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Annotations'), findsOneWidget);
      expect(find.text('Default highlight color'), findsOneWidget);
    });
  });
}
