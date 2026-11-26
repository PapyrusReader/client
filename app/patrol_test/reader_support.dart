import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/bookmarks/bookmark_list_item.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:patrol/patrol.dart';

import 'journey_support.dart';

final surface = find.byKey(const ValueKey('reader-content'));
final nextPage = find.byTooltip('Next');

extension ReaderJourney on PatrolIntegrationTester {
  ReaderController get reader => tester.widget<PapyrusReader>(find.byType(PapyrusReader)).controller!;

  Future<void> controls() async {
    await this(surface).waitUntilExists(timeout: const Duration(seconds: 60));

    if (nextPage.hitTestable().evaluate().isEmpty) {
      await tester.tapAt(tester.getRect(surface).center);
      await tester.pumpAndSettle();
    }

    await this(nextPage).waitUntilVisible();
  }

  Future<void> action(String label) async {
    final toolbar = find.byTooltip(label).hitTestable();

    if (toolbar.evaluate().isNotEmpty) {
      await this(toolbar).tap();
    } else {
      await this(find.byTooltip('More reader actions')).tap();
      await this(label).tap();
    }
  }

  Future<void> openBookmark() async {
    await this(find.byTooltip('Back').first).tap();
    final deadline = DateTime.now().add(const Duration(seconds: 10));

    while (surface.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(surface, findsNothing, reason: 'Reader should finish saving and close before opening Bookmarks.');
    await visit('/library/bookmarks');
    await this(find.byType(BookmarkListItem)).tap();
    await controls();
  }

  List<({String word, Offset point, Color? color})> waypoints() {
    final area = tester.getRect(surface);
    final words = <({String word, Offset point, Color? color})>[];
    final paragraphs = find.descendant(of: surface, matching: find.byType(RichText));

    for (final element in paragraphs.evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      final text = paragraph.text.toPlainText();

      for (final match in RegExp(r'Waypoint\d{3}').allMatches(text)) {
        final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: match.start, extentOffset: match.end));

        if (boxes.isEmpty) {
          continue;
        }

        final point = paragraph.localToGlobal(boxes.first.toRect().center);

        if (area.contains(point)) {
          final span = paragraph.text.getSpanForPosition(TextPosition(offset: match.start + 1));
          words.add((word: match.group(0)!, point: point, color: span?.style?.backgroundColor));
        }
      }
    }

    return words..sort((left, right) => left.point.dy.compareTo(right.point.dy));
  }
}
