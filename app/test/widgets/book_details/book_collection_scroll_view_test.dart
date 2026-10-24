import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/book_collection_scroll_view.dart';

void main() {
  testWidgets('last collection action scrolls above the FAB', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    int? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
          body: BookCollectionScrollView(
            header: const SizedBox(height: 64, child: Text('Notes')),
            itemCount: 20,
            itemBuilder: (context, index) => ListTile(
              title: Text('Note $index'),
              trailing: IconButton(
                tooltip: 'Edit note $index',
                icon: const Icon(Icons.edit),
                onPressed: () => selected = index,
              ),
            ),
            emptyState: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -10000));
    await tester.pumpAndSettle();
    final action = find.byTooltip('Edit note 19');
    expect(tester.getRect(action).bottom, lessThan(tester.getRect(find.byType(FloatingActionButton)).top));
    await tester.tap(action);
    expect(selected, 19);
    expect(tester.takeException(), isNull);
  });
}
