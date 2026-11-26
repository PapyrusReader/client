import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:patrol/patrol.dart';

import 'journey_support.dart';
import 'reader_support.dart';

void main() {
  patrolTest('EPUB bookmark opens the same passage after changing font size', ($) async {
    await $.startGuest();
    final book = await $.seedBook('Waypoints', format: BookFormat.epub);
    await $.visit('/library/read/${book.id}');
    await $.controls();

    for (var page = 0; page < 4; page++) {
      await $(nextPage).tap();
    }

    final marked = $.waypoints().first.word;
    expect(marked, isNot('Waypoint000'));
    await $.action('Add bookmark');
    await $(find.byTooltip('Remove bookmark')).waitUntilExists();
    final originalSize = $.reader.preferences.fontSize;
    await $(find.byTooltip('Reading settings')).tap();
    await $('Font size').waitUntilVisible();
    final setting = find.ancestor(of: find.text('Font size'), matching: find.byType(Column)).first;
    final slider = find.descendant(of: setting, matching: find.byType(Slider));
    await $.tester.ensureVisible(slider);
    final bounds = $.tester.getRect(slider);
    await $.tester.tapAt(Offset(bounds.left + bounds.width * .43, bounds.center.dy));
    await $.tester.pumpAndSettle();
    Navigator.of($.tester.element(slider)).pop();
    await $.tester.pumpAndSettle();
    expect($.reader.preferences.fontSize, greaterThan(originalSize));
    await $(nextPage).tap();
    await $(nextPage).tap();
    expect($.waypoints().map((marker) => marker.word), isNot(contains(marked)));
    await $.openBookmark();
    expect($.waypoints().map((marker) => marker.word), contains(marked));
  });
}
