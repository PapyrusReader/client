import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/reader/reader_panel_route.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

void main() {
  for (final host in ['light', 'dark', 'eink']) {
    for (final reading in [Brightness.light, Brightness.dark]) {
      for (final width in [600.0, 1200.0]) {
        testWidgets('settings menu contrast: app $host, reader $reading, width $width', (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final controller = ReaderController(
            initialPreferences: ReaderPreferences(brightness: reading),
            registry: ReaderEngineRegistry([
              ReaderEngineRegistration(
                formats: const {ReaderFormat.pdf},
                factory: () => PdfReaderEngine(facadeFactory: (_) async => _ThemePdfFacade()),
              ),
            ]),
          );

          addTearDown(controller.dispose);

          final hostTheme = switch (host) {
            'dark' => AppTheme.dark,
            'eink' => AppTheme.eink,
            _ => AppTheme.light,
          };

          await tester.pumpWidget(
            MaterialApp(
              theme: hostTheme,
              home: PapyrusReader(
                document: ReaderDocument(id: 'theme', format: ReaderFormat.pdf, loadBytes: () async => Uint8List(0)),
                controller: controller,
                builders: ReaderUiBuilders(compactPanelRoute: buildReaderPanelRoute),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(find.byTooltip('Reading settings'), findsNothing);
          await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('reader-content'))));
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Reading settings'));
          await tester.pumpAndSettle();
          final label = find.text('Reading mode');
          final readerTheme = Theme.of(tester.element(label));
          final readerColors = readerTheme.colorScheme;
          expect(readerColors, hostTheme.colorScheme);

          if (host == 'eink') {
            expect(readerTheme.extension<AppMotion>()!.reduceAnimations, isTrue);
            expect(readerTheme.inputDecorationTheme.hintFadeDuration, Duration.zero);
            expect(readerTheme.filledButtonTheme.style!.animationDuration, Duration.zero);
            expect(readerTheme.splashFactory, same(NoSplash.splashFactory));
          }

          final labelText = tester.widget<RichText>(find.descendant(of: label, matching: find.byType(RichText)).first);
          expect(labelText.text.style!.color, hostTheme.inputDecorationTheme.labelStyle!.color);
          await tester.tap(find.text('Paginated').first);
          await tester.pumpAndSettle();
          final option = find.text('Continuous scroll').last;
          final menuTheme = Theme.of(tester.element(option));
          expect(menuTheme.canvasColor, hostTheme.canvasColor);

          final optionText = tester.widget<RichText>(
            find.descendant(of: option, matching: find.byType(RichText)).first,
          );

          final foreground = optionText.text.style!.color!.computeLuminance();
          final background = menuTheme.canvasColor.computeLuminance();

          expect(
            (math.max(foreground, background) + .05) / (math.min(foreground, background) + .05),
            greaterThanOrEqualTo(4.5),
          );

          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(controller.preferences.layoutMode, ReaderLayoutMode.scroll);
          // Page appearance changes must not recolor the app's controls.
          await tester.tap(find.text(reading == Brightness.light ? 'Night' : 'Light'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Single').first);
          await tester.pumpAndSettle();
          final columns = find.text('Double').last;
          final changedTheme = Theme.of(tester.element(columns));
          expect(changedTheme.colorScheme, hostTheme.colorScheme);
          expect(controller.preferences.brightness, reading == Brightness.light ? Brightness.dark : Brightness.light);
          expect(changedTheme.canvasColor, hostTheme.canvasColor);

          final columnsText = tester.widget<RichText>(
            find.descendant(of: columns, matching: find.byType(RichText)).first,
          );

          final changedForeground = columnsText.text.style!.color!.computeLuminance();
          final changedBackground = changedTheme.canvasColor.computeLuminance();

          expect(
            (math.max(changedForeground, changedBackground) + .05) /
                (math.min(changedForeground, changedBackground) + .05),
            greaterThanOrEqualTo(4.5),
          );

          await tester.tap(columns);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

final class _ThemePdfFacade implements PdfFacade {
  @override
  int get pageCount => 3;

  @override
  List<PdfFacadeOutlineEntry> get outline => const [];

  @override
  Future<void> showPage(int pageIndex, double pageOffset) async {}

  @override
  Widget buildViewport(PdfViewportConfiguration configuration) => const SizedBox.expand();
}
