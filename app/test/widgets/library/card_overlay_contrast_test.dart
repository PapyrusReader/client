import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_card.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/shelves/shelf_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  final themes = {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'high contrast light': AppTheme.highContrastLight,
    'high contrast dark': AppTheme.highContrastDark,
    'e-ink': AppTheme.eink,
  };

  final job = AcquisitionJob.fromJson({
    'job_id': 'contrast-job',
    'title': 'Downloading book',
    'status': 'queued',
  });

  final cards = <String, Widget>{
    'favorite': BookCard(book: buildTestBook(), isFavorite: true),
    'selected book': BookCard(
      book: buildTestBook(),
      isFavorite: false,
      isSelectionMode: true,
      isSelected: true,
    ),
    'selected download': AcquisitionPlaceholderCard(job: job, isSelectionMode: true, isSelected: true),
    'unselected book': BookCard(book: buildTestBook(), isFavorite: false, isSelectionMode: true),
    'unselected download': AcquisitionPlaceholderCard(job: job, isSelectionMode: true),
  };

  for (final theme in themes.entries) {
    testWidgets('grid cards share a visible border in ${theme.key}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.value,
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 160, height: 240, child: BookCard(book: buildTestBook(), isFavorite: false)),
                SizedBox(width: 160, height: 240, child: ShelfCard(shelf: buildTestShelf())),
                SizedBox(width: 160, height: 240, child: AcquisitionPlaceholderCard(job: job)),
              ],
            ),
          ),
        ),
      );

      final materials = tester.widgetList<Material>(
        find.byWidgetPredicate((widget) => widget is Material && widget.type == MaterialType.card),
      );

      expect(materials, hasLength(3));
      expect(materials.map((material) => material.elevation), everyElement(0));
      expect(materials.map((material) => material.borderOnForeground), everyElement(isTrue));
      final shape = materials.first.shape! as RoundedRectangleBorder;
      expect(materials.map((material) => material.shape), everyElement(shape));

      final eink = theme.key == 'e-ink';
      expect(shape.side.style, BorderStyle.solid);
      expect(shape.side.width, eink ? BorderWidths.einkDefault : BorderWidths.thin);
      expect(shape.borderRadius, eink ? BorderRadius.zero : BorderRadius.circular(AppRadius.card));

      if (eink) {
        expect(shape.side.color, Colors.black);
      }

      final luminances = [shape.side.color.computeLuminance(), theme.value.scaffoldBackgroundColor.computeLuminance()]
        ..sort();
      final contrast = (luminances.last + 0.05) / (luminances.first + 0.05);
      expect(contrast, greaterThanOrEqualTo(eink || theme.key.startsWith('high contrast') ? 3 : 1.8));
      expect(tester.takeException(), isNull);
    });

    for (final card in cards.entries) {
      testWidgets('${card.key} stays visible over cover colors in ${theme.key}', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: Scaffold(
              body: SizedBox(width: 200, height: 300, child: card.value),
            ),
          ),
        );

        final icon = switch (card.key) {
          'favorite' => Icons.favorite,
          'selected book' || 'selected download' => Icons.check_circle,
          _ => Icons.radio_button_unchecked,
        };

        final finder = find.byIcon(icon);
        final foreground = tester.widget<Icon>(finder).color!;
        final material = tester.widget<Material>(find.ancestor(of: finder, matching: find.byType(Material)).first);

        for (final cover in [Colors.white, Colors.black, Colors.red, Colors.green, Colors.blue]) {
          final background = Color.alphaBlend(material.color!, cover);
          final foregroundLuminance = foreground.computeLuminance();
          final backgroundLuminance = background.computeLuminance();
          final lighter = foregroundLuminance > backgroundLuminance ? foregroundLuminance : backgroundLuminance;
          final darker = foregroundLuminance < backgroundLuminance ? foregroundLuminance : backgroundLuminance;
          expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(3), reason: 'Cover: $cover');
        }

        expect(tester.takeException(), isNull);
      });
    }
  }
}
