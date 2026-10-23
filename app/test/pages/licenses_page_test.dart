import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/pages/licenses_page.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';

void main() {
  setUp(() {
    LicenseRegistry.reset();
    LicenseRegistry.addLicense(
      () => Stream.fromIterable([
        const LicenseEntryWithLineBreaks(['alpha', 'shared'], 'Alpha license text'),
        const LicenseEntryWithLineBreaks(['beta', 'shared'], 'Beta license text'),
      ]),
    );
  });
  tearDown(LicenseRegistry.reset);

  testWidgets('wide licenses show all notices and switch without animation', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const LicensesPage()));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPageHeader), findsOneWidget);
    expect(find.text('Alpha license text'), findsOneWidget);
    await tester.tap(find.text('shared'));
    await tester.pump();
    expect(find.text('Alpha license text'), findsOneWidget);
    expect(find.text('Beta license text'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact license navigation and back are immediate', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.eink, home: const LicensesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta'));
    await tester.pump();
    expect(find.text('Beta license text'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pageBack();
    await tester.pump();
    expect(find.text('Licenses'), findsOneWidget);
    expect(find.text('Beta license text'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
