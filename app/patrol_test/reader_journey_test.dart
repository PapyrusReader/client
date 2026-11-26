import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/main.dart' as app;
import 'package:patrol/patrol.dart';

const fixtureName = 'PapyrusJourney';
final chapter = find.textContaining(RegExp(r'Chapter \d+ of \d+'));
final next = find.byTooltip('Next');

Future<void> pickBook(PatrolIntegrationTester $) async {
  if (Platform.isAndroid) {
    final android = $.platform.android;
    const file = AndroidSelector(textContains: fixtureName);
    await android.waitUntilVisible(const AndroidSelector(contentDescription: 'Show roots'));

    if ((await android.getNativeViews(file)).roots.isEmpty) {
      await android.tap(const AndroidSelector(contentDescription: 'Show roots'));
      await android.tap(const AndroidSelector(text: String.fromEnvironment('EMULATOR_MODEL')));

      if ((await android.getNativeViews(file)).roots.isEmpty) {
        await android.tap(const AndroidSelector(text: 'Download'));
      }
    }

    await android.tap(file);
    return;
  }

  final ios = $.platform.ios;
  await ios.tap(const IOSSelector(label: 'Browse'));
  await ios.tap(const IOSSelector(labelContains: 'On My iPhone'));
  await ios.tap(const IOSSelector(labelContains: fixtureName));
  await ios.tap(const IOSSelector(label: 'Open'));
}

Future<void> showReaderControls(PatrolIntegrationTester $) async {
  final surface = find.byKey(const ValueKey('reader-content'));
  await $(surface).waitUntilExists(timeout: const Duration(seconds: 60));

  if (next.hitTestable().evaluate().isEmpty) {
    await $.tester.tapAt($.tester.getRect(surface).center);
    await $.tester.pump();
  }

  await $(next).waitUntilVisible();
}

void main() {
  patrolTest('import a book, explore the reader and resume the saved chapter', ($) async {
    await app.main();
    await $.tester.pump();
    await $('Continue offline').tap();
    await $(find.text('Add book').hitTestable().first).tap();
    await $('Import digital books').tap();
    await $('Browse files').tap();
    await pickBook($);
    await $(find.textContaining('$fixtureName.epub')).waitUntilExists();
    await $('Import').tap();
    await $('Done').tap(visibleTimeout: const Duration(seconds: 60));
    await $(find.textContaining('Frankenstein').first).tap();
    await $('Read').tap();
    await showReaderControls($);
    await $(chapter).waitUntilExists();
    const seed = int.fromEnvironment('JOURNEY_SEED', defaultValue: 42);
    final random = Random(seed);
    var moves = 0;

    for (var step = 0; step < 5; step++) {
      final before = $.tester.widget<Text>(chapter).data!;
      final choice = random.nextInt(3);
      final goBack = choice == 1 && moves > 1;

      if (choice == 2 && moves > 0) {
        debugPrint('Reader journey seed=$seed step=$step background and return');
        await $.platform.mobile.pressHome();
        await $.platform.mobile.openApp();
        await $(find.text(before)).waitUntilExists();
        continue;
      }

      final label = goBack ? 'Previous' : 'Next';
      debugPrint('Reader journey seed=$seed step=$step tap $label');
      await $(find.byTooltip(label)).tap();
      await $(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data != before && (widget.data?.contains(RegExp(r'Chapter \d+ of')) ?? false),
        ),
      ).waitUntilExists();
      moves += goBack ? -1 : 1;
    }

    final saved = $.tester.widget<Text>(chapter).data!;
    await $(find.byTooltip('Back').first).tap();
    await $('Continue').tap();
    await showReaderControls($);
    await $(find.text(saved)).waitUntilExists();
  });
}
