import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/widgets/shelves/move_to_shelf_sheet.dart';
import 'package:papyrus/widgets/topics/manage_topics_sheet.dart';

import '../../helpers/test_helpers.dart';

void main() {
  final dataStore = DataStore()..loadData(shelves: const [], tags: const []);

  Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      createTestPage(
        page: Scaffold(body: sheet),
        dataStore: dataStore,
        screenSize: const Size(800, 1200),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('topics empty state is centered across the sheet', (tester) async {
    await pumpSheet(tester, const ManageTopicsSheet(bulkBookIds: ['book-1']));

    final title = find.text('No topics yet');
    expect(title, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(400, 20));
  });

  testWidgets('shelves empty state is present and centered across the sheet', (tester) async {
    await pumpSheet(tester, const MoveToShelfSheet(bulkBookIds: ['book-1']));

    final title = find.text('No shelves yet');
    expect(title, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(400, 20));
  });
}
