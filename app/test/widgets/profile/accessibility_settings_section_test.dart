import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/app_accessibility.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/profile/accessibility_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(AppTheme.dyslexiaFontFamily);
    loader.addFont(rootBundle.load('fonts/OpenDyslexic/OpenDyslexic-Regular.otf'));
    await loader.load();
  });

  test('bundles regular, bold, italic and bold italic fonts with their license', () async {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['family'] == AppTheme.dyslexiaFontFamily,
    );
    final fonts = (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(fonts.map((font) => (font['weight'] ?? 400, font['style'] ?? 'normal')).toSet(), {
      (400, 'normal'),
      (700, 'normal'),
      (400, 'italic'),
      (700, 'italic'),
    });

    for (final font in fonts) {
      final data = await rootBundle.load(font['asset'] as String);
      expect(ascii.decode(data.buffer.asUint8List(data.offsetInBytes, 4)), 'OTTO');
    }

    expect(await rootBundle.loadString('fonts/OpenDyslexic/OFL.txt'), contains('SIL OPEN FONT LICENSE'));
  });

  for (final (mode, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('eink', AppTheme.eink),
    ('high contrast light', AppTheme.highContrastLight),
    ('high contrast dark', AppTheme.highContrastDark),
  ]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets('$mode at $width changes preferences with large text and persists them', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'theme_mode': mode});
        final storage = await SharedPreferences.getInstance();
        final preferences = PreferencesProvider(storage);
        addTearDown(preferences.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: preferences,
            child: Consumer<PreferencesProvider>(
              builder: (context, preferences, child) => MaterialApp(
                theme: AppTheme.withTypography(theme, dyslexiaFont: preferences.dyslexiaFont),
                themeAnimationDuration: Duration.zero,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
                  child: AppAccessibilityScope(preferences: preferences, child: child!),
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AccessibilitySettingsSection(isDesktop: width >= 1024),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Interface font'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('OpenDyslexic').last);
        await tester.tap(find.text('OpenDyslexic').last);
        await tester.pumpAndSettle();
        expect(preferences.dyslexiaFont, isTrue);
        final preview = find.text('The quick brown fox jumps over the lazy dog.');
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: preview, matching: find.byType(RichText)),
        );
        expect(paragraph.text.style?.fontFamily, AppTheme.dyslexiaFontFamily);

        await tester.ensureVisible(find.text('Interface text enlargement'));
        await tester.tap(find.text('Interface text enlargement'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('+100%'));
        await tester.tap(find.text('+100%'));
        await tester.pumpAndSettle();
        expect(preferences.interfaceTextEnlargement, 2);
        expect(MediaQuery.textScalerOf(tester.element(preview)).scale(16), 64);
        await tester.ensureVisible(find.text('Bold interface text'));
        await tester.tap(find.text('Bold interface text'));
        await tester.pumpAndSettle();
        expect(preferences.boldInterfaceText, isTrue);
        await tester.ensureVisible(find.text('Increase contrast'));
        await tester.tap(find.text('Increase contrast'));
        await tester.pumpAndSettle();
        expect(preferences.increaseContrast, mode != 'eink');
        await storage.reload();
        final restored = PreferencesProvider(storage);
        addTearDown(restored.dispose);
        expect(restored.interfaceTextEnlargement, 2);
        expect(restored.boldInterfaceText, isTrue);
        expect(restored.dyslexiaFont, isTrue);
        expect(restored.defaultFont, 'Georgia');
      });
    }
  }
}
