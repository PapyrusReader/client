import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book_details/empty_annotations_state.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('digital annotations explain highlighting without offering manual entry', (tester) async {
    await tester.pumpWidget(createTestApp(child: const EmptyAnnotationsState()));
    expect(find.text('No annotations yet'), findsOneWidget);
    expect(find.text('Highlight text while reading to create annotations.'), findsOneWidget);
    expect(find.text('Add annotation'), findsNothing);
  });

  testWidgets('physical annotations explain manual entry and invoke the add action', (tester) async {
    var additions = 0;

    await tester.pumpWidget(
      createTestApp(
        child: EmptyAnnotationsState(isPhysical: true, onAddAnnotation: () => additions++),
      ),
    );

    expect(find.text('No annotations yet'), findsOneWidget);
    expect(find.text("Add passages you've highlighted or underlined in your book."), findsOneWidget);
    await tester.tap(find.text('Add annotation'));
    expect(additions, 1);
  });
}
