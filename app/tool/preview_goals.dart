import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_theme.dart';
import '../integration_test/support/tracking_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = TrackingValidationApp();
  await app.initialize();
  globalContext.setProperty(
    'trackingValidation'.toJS,
    (() => jsonEncode({
      'activities': app.store.readingActivities.map((value) => value.toJson()).toList(),
      'seconds': app.goals.current.first.seconds,
      'pages': app.goals.current.first.pages,
    }).toJS).toJS,
  );
  globalContext.setProperty(
    'trackingAppearance'.toJS,
    ((JSString name, JSNumber scale) {
      final theme = switch (name.toDart) {
        'light' => AppTheme.light,
        'eink' => AppTheme.eink,
        _ => AppTheme.dark,
      };
      app.preferences.themeModePref = name.toDart;
      runApp(app.build(theme: theme, textScale: scale.toDartDouble));
    }).toJS,
  );
  globalContext.setProperty(
    'trackingRoute'.toJS,
    ((JSString format) {
      if (format.toDart.isEmpty) {
        app.router.go('/');
      } else {
        app.router.goNamed('BOOK_READER', pathParameters: {'bookId': format.toDart});
      }
    }).toJS,
  );
  runApp(app.build());
}
