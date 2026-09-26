import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/profile/library_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LibrarySettingsSection', () {
    late PreferencesProvider prefsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'default_view_mode': 'grid',
        'default_sort_order': 'date_added',
        'metadata_source': 'Open Library',
        'annotation_export_format': 'Markdown',
      });
      final prefs = await SharedPreferences.getInstance();
      prefsProvider = PreferencesProvider(prefs);
    });

    Widget buildSection({bool isDesktop = false}) {
      return ChangeNotifierProvider<PreferencesProvider>.value(
        value: prefsProvider,
        child: MaterialApp(
          home: Scaffold(body: LibrarySettingsSection(isDesktop: isDesktop)),
        ),
      );
    }

    testWidgets('renders mobile library settings and rows', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: false));

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Default view'), findsOneWidget);
      expect(find.text('Default sort'), findsOneWidget);
      expect(find.text('Metadata source'), findsOneWidget);
      expect(find.text('Export format'), findsOneWidget);
    });

    testWidgets('renders desktop display and data configuration cards', (tester) async {
      await tester.pumpWidget(buildSection(isDesktop: true));

      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Default view mode'), findsOneWidget);
      expect(find.text('Default sort order'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Metadata source'), findsOneWidget);
      expect(find.text('Annotation export format'), findsOneWidget);
    });
  });
}
