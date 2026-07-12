import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/pages/goals_page.dart';

import '../helpers/test_helpers.dart';

void main() {
  Future<void> pumpEmptyGoalsPage(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final dataStore = DataStore()..loadData(readingGoals: const []);
    await tester.pumpWidget(createTestPage(page: const GoalsPage(), dataStore: dataStore, screenSize: size));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(400, 800), const Size(1200, 800)]) {
    testWidgets('empty state is vertically centered at ${size.width.toInt()}px', (tester) async {
      await pumpEmptyGoalsPage(tester, size);

      final titleCenter = tester.getCenter(find.text('No goals yet'));
      expect(titleCenter.dy, closeTo(size.height / 2, 100));
    });
  }
}
