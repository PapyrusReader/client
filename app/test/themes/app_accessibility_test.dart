import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/app_accessibility.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize < 20 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test('additional enlargement preserves the system curve', () {
    const scaler = InterfaceTextScaler(_NonlinearScaler(), 1.5);
    expect(scaler.scale(16), 48);
    expect(scaler.scale(24), 54);
  });

  testWidgets('interface overrides and live system changes leave reader text independent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesProvider(await SharedPreferences.getInstance());
    addTearDown(preferences.dispose);
    final system = ValueNotifier(const MediaQueryData(textScaler: _NonlinearScaler()));
    addTearDown(system.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => ListenableBuilder(
          listenable: Listenable.merge([preferences, system]),
          builder: (context, _) => MediaQuery(
            data: system.value,
            child: AppAccessibilityScope(preferences: preferences, child: child!),
          ),
        ),
        home: const Scaffold(
          body: Column(
            children: [
              TextField(decoration: InputDecoration(labelText: 'Interface input')),
              ReaderSystemTextScope(
                child: TextField(decoration: InputDecoration(labelText: 'Reader input')),
              ),
            ],
          ),
        ),
      ),
    );
    preferences.interfaceTextEnlargement = 2;
    preferences.boldInterfaceText = true;
    await tester.pumpAndSettle();
    final interface = tester.widget<EditableText>(find.byType(EditableText).first);
    final reader = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(MediaQuery.textScalerOf(tester.element(find.byType(EditableText).first)).scale(16), 64);
    expect(interface.style.fontWeight, FontWeight.bold);
    expect(MediaQuery.textScalerOf(tester.element(find.byType(EditableText).last)).scale(16), 32);
    expect(reader.style.fontWeight, isNot(FontWeight.bold));
    preferences.boldInterfaceText = false;
    system.value = const MediaQueryData(textScaler: TextScaler.linear(1.5), boldText: true, disableAnimations: true);
    await tester.pumpAndSettle();
    expect(MediaQuery.textScalerOf(tester.element(find.byType(EditableText).first)).scale(16), 48);
    expect(MediaQuery.textScalerOf(tester.element(find.byType(EditableText).last)).scale(16), 24);
    expect(tester.widget<EditableText>(find.byType(EditableText).last).style.fontWeight, FontWeight.bold);
    expect(AppMotion.disabled(tester.element(find.byType(EditableText).first)), isTrue);
    preferences.interfaceTextEnlargement = 1;
    await tester.pumpAndSettle();
    expect(MediaQuery.textScalerOf(tester.element(find.byType(EditableText).first)).scale(16), 24);
  });

  testWidgets('disabled toggle exposes its state without an activation action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsToggleRow(label: 'Increase contrast', value: true, onChanged: null)),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Increase contrast')),
        isSemantics(
          hasEnabledState: true,
          isEnabled: false,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: false,
          isFocusable: false,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final theme in [
    AppTheme.light,
    AppTheme.dark,
    AppTheme.eink,
    AppTheme.highContrastLight,
    AppTheme.highContrastDark,
  ]) {
    testWidgets(
      'toggle has one labeled state and supports pointer, keyboard and semantics in ${theme.brightness}, e-ink ${theme.extension<AppMotion>() != null}',
      (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();

        final value = ValueNotifier(false);
        addTearDown(value.dispose);
        var changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: value,
                builder: (_, enabled, _) => SettingsToggleRow(
                  label: 'Bold interface text',
                  value: enabled,
                  onChanged: (next) {
                    changes++;
                    value.value = next;
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Bold interface text'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Bold interface text')),
          matchesSemantics(
            label: 'Bold interface text',
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
        await tester.tap(find.text('Bold interface text'));
        await tester.pumpAndSettle();
        expect(changes, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(changes, 2);
        expect(value.value, isFalse);
        final node = tester.getSemantics(find.bySemanticsLabel('Bold interface text'));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(changes, 3);
        expect(value.value, isTrue);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      },
    );
  }
}
