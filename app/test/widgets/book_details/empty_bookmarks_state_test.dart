import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/empty_bookmarks_state.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('digital bookmarks explain highlighting without offering manual entry', (tester) async {
    await tester.pumpWidget(createTestApp(child: const EmptyBookmarksState()));
    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(find.text('Bookmarks you create while reading will appear here.'), findsOneWidget);
    expect(find.text('Add bookmark'), findsNothing);
  });

  testWidgets('physical bookmarks explain manual entry and invoke the add action', (tester) async {
    var additions = 0;

    await tester.pumpWidget(
      createTestApp(
        child: EmptyBookmarksState(isPhysical: true, onAddBookmark: () => additions++),
      ),
    );

    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(find.text("Save pages you want to return to later."), findsOneWidget);
    await tester.tap(find.text('Add bookmark'));
    expect(additions, 1);
  });
}
