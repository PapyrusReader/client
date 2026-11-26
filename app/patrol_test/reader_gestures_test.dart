import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/widgets/book_details/annotation_card.dart';
import 'package:patrol/patrol.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'journey_support.dart';
import 'reader_support.dart';

void main() {
  patrolTest('a highlight edited in Annotations paints the same passage and can be deleted', ($) async {
    await $.startGuest();
    final book = await $.seedBook('Highlighted waypoints', format: BookFormat.epub);
    await $.visit('/library/read/${book.id}');
    await $.controls();
    final marker = $.waypoints()[1];
    await $.tester.longPressAt(marker.point);
    await $('Annotate').tap();
    await $(find.text(marker.word)).waitUntilExists();
    await $('Save').tap();
    await $.controls();
    await $(nextPage).tap();
    expect($.waypoints().map((item) => item.word), isNot(contains(marker.word)));
    await $.visit('/library/annotations');
    final card = find.byType(AnnotationCard);
    await $(card).waitUntilVisible();
    await $.tester.longPress(card);
    await $('Edit annotation').tap();
    final blue = find.byKey(const Key('annotation-color-blue'));
    await $.tester.ensureVisible(blue);
    await $(blue).tap();
    await $('Save').tap();
    await $(card).tap();
    await $.controls();
    final highlight = $.waypoints().singleWhere((item) => item.word == marker.word);
    expect(highlight.color, HighlightColor.blue.accentColor.withValues(alpha: .4));
    await $.visit('/library/annotations');
    await $(card).waitUntilVisible();
    await $.tester.longPress(card);
    await $('Delete annotation').tap();
    await $('Delete').tap();
    await $.reopenGuest();
    await $.visit('/library/annotations');
    expect(card, findsNothing);
    await $.visit('/library/read/${book.id}');
    await $.controls();
    if (!$.waypoints().any((item) => item.word == marker.word)) {
      await $(find.byTooltip('Previous')).tap();
    }

    final restored = $.waypoints().singleWhere((item) => item.word == marker.word);
    expect(restored.color, isNull);
  });

  patrolTest('PDF pan stays on the page and a bookmark reopens the labeled destination', ($) async {
    await $.startGuest();
    final book = await $.seedBook('Landmarks', format: BookFormat.pdf);
    await $.visit('/library/read/${book.id}');
    await $.controls();
    final document = PdfDocument(inputBytes: base64Decode(const String.fromEnvironment('JOURNEY_PDF')));
    addTearDown(document.dispose);

    String currentLabel() {
      final index = $.reader.pdfTools!.pageNumber - 1;
      return PdfTextExtractor(document).extractText(startPageIndex: index, endPageIndex: index).trim();
    }

    expect(currentLabel(), 'Harbor');
    final initialZoom = $.reader.pdfTools!.zoom;

    for (var step = 0; step < 4; step++) {
      await $.action('Zoom in by 5%');
    }

    expect($.reader.pdfTools!.zoom, greaterThan(initialZoom));
    await $.tester.dragFrom($.tester.getRect(surface).center, const Offset(-210, 0));
    await $.tester.pumpAndSettle();
    expect(currentLabel(), 'Harbor');
    await $.controls();
    await $(nextPage).tap();
    expect(currentLabel(), 'Summit');
    await $.action('Add bookmark');
    await $(nextPage).tap();
    expect(currentLabel(), 'Forest');
    await $.openBookmark();
    expect(currentLabel(), 'Summit');
  });
}
