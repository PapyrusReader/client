import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_card.dart';
import 'package:papyrus/widgets/library/book_card.dart';

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
