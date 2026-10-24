import 'package:flutter/material.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/app_theme.dart';

/// Preserves the platform's nonlinear curve while adding interface enlargement.
@immutable
class InterfaceTextScaler extends TextScaler {
  const InterfaceTextScaler(this.system, this.multiplier);

  final TextScaler system;
  final double multiplier;

  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is InterfaceTextScaler && other.system == system && other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(system, multiplier);
}

/// Wraps the navigator so preferences also reach dialogs and sheets.
class AppAccessibilityScope extends StatelessWidget {
  const AppAccessibilityScope({super.key, required this.preferences, required this.child});

  final PreferencesProvider preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final system = MediaQuery.of(context);
    final theme = Theme.of(context);
    final boldText = system.boldText || preferences.boldInterfaceText;

    return _SystemTextSettings(
      textScaler: system.textScaler,
      boldText: system.boldText,
      theme: theme,
      child: MediaQuery(
        data: system.copyWith(
          textScaler: preferences.interfaceTextEnlargement == 1
              ? system.textScaler
              : InterfaceTextScaler(system.textScaler, preferences.interfaceTextEnlargement),
          boldText: boldText,
        ),
        child: Theme(
          data: AppTheme.withTypography(theme, boldText: boldText),
          child: AppMotionScope(
            reduceAnimations: preferences.isEinkMode || preferences.reduceAnimations,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The embedded reader owns text sizing. Keep OS accessibility, but remove the
/// extra interface overrides, including from reader panels on the root navigator.
class ReaderSystemTextScope extends StatelessWidget {
  const ReaderSystemTextScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final system = context.dependOnInheritedWidgetOfExactType<_SystemTextSettings>();

    if (system == null) {
      return child;
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: system.textScaler, boldText: system.boldText),
      child: Theme(
        data: AppTheme.withTypography(system.theme, boldText: system.boldText),
        child: child,
      ),
    );
  }
}

class _SystemTextSettings extends InheritedWidget {
  const _SystemTextSettings({
    required this.textScaler,
    required this.boldText,
    required this.theme,
    required super.child,
  });

  final TextScaler textScaler;
  final bool boldText;
  final ThemeData theme;

  @override
  bool updateShouldNotify(_SystemTextSettings oldWidget) =>
      textScaler != oldWidget.textScaler || boldText != oldWidget.boldText || theme != oldWidget.theme;
}
