import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('prepared licenses render on the first frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const LicensesPage(
          initialLicenses: {
            'alpha': [
              LicenseEntryWithLineBreaks(['alpha'], 'Alpha license text'),
            ],
          },
        ),
      ),
    );

    expect(find.widgetWithText(ListTile, 'alpha'), findsOneWidget);
    expect(find.text('Loading licenses…'), findsNothing);
  });

  testWidgets('fast loads never flash loading feedback', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const LicensesPage()));
    expect(find.text('Loading licenses…'), findsNothing);
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'alpha'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Loading licenses…'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets('slow load feedback stays readable before completion, fails=$fails', (tester) async {
      final result = Completer<LicenseEntry>();
      LicenseRegistry.reset();
      LicenseRegistry.addLicense(() => Stream.fromFuture(result.future));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const LicensesPage()));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('Loading licenses…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Loading licenses…'), findsOneWidget);

      if (fails) {
        result.completeError(StateError('License load failed'));
      } else {
        result.complete(const LicenseEntryWithLineBreaks(['alpha'], 'Alpha license text'));
      }

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(find.text('Loading licenses…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Loading licenses…'), findsNothing);
      expect(
        fails ? find.text('Could not load licenses. Retry') : find.widgetWithText(ListTile, 'alpha'),
        findsOneWidget,
      );

      if (fails) {
        LicenseRegistry.reset();
        LicenseRegistry.addLicense(
          () => Stream.value(const LicenseEntryWithLineBreaks(['alpha'], 'Alpha license text')),
        );

        await tester.tap(find.text('Could not load licenses. Retry'));
        await tester.pump();
        expect(find.text('Loading licenses…'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'alpha'), findsOneWidget);
      }
    });
  }

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

  testWidgets('scrolling the selected license never paints over the header', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captureKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RepaintBoundary(
          key: captureKey,
          child: LicensesPage(
            initialLicenses: {
              for (var index = 0; index < 40; index++)
                'package-${index.toString().padLeft(2, '0')}': [
                  const LicenseEntryWithLineBreaks(['package'], 'License text'),
                ],
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final headerBottom = tester.getBottomLeft(find.byType(LibraryPageHeader)).dy.floor();

    Future<List<int>> headerPixels() async {
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = bytes!.buffer.asUint8List(0, image.width * headerBottom * 4).toList();
      image.dispose();
      return pixels;
    }

    final before = await tester.runAsync(headerPixels);
    final list = find.byKey(const PageStorageKey('license-packages'));
    await tester.drag(list, const Offset(0, -50));
    await tester.pumpAndSettle();
    final after = await tester.runAsync(headerPixels);
    expect(listEquals(before, after), isTrue, reason: 'Selection ink must stay below the header while scrolling.');
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
