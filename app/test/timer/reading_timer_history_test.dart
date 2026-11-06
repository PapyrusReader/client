import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/widgets/timer/reading_timer_history.dart';
import 'package:provider/provider.dart';

void main() {
  final date = DateTime.utc(2026, 11, 6, 12);
  late DataStore store;

  setUp(() => store = DataStore(bookRepository: InMemoryBookRepository()));
  tearDown(() => store.dispose());

  ReadingActivity entry(
    String id, {
    int minute = 0,
    int seconds = 60,
    String? sessionId,
    String kind = 'reading',
    String? correctionOf,
  }) => ReadingActivity(
    id: id,
    bookId: 'book',
    bookTitle: 'Book $id',
    sessionId: sessionId,
    deviceType: 'physical_timer',
    startTime: date.add(Duration(minutes: minute)),
    endTime: date.add(Duration(minutes: minute, seconds: seconds)),
    createdAt: date,
    kind: kind,
    correctionOf: correctionOf,
  );

  Future<void> pump(WidgetTester tester, {double width = 500, double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: ReadingTimerHistory(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('history groups intervals without counting pauses and orders newest first', (tester) async {
    await store.commitTracking(
      activities: [
        entry('first', seconds: 120, sessionId: 'shared'),
        entry('second', minute: 10, seconds: 180, sessionId: 'shared'),
        entry('latest', minute: 30, seconds: 42),
        entry('completion', minute: 40, kind: 'completion'),
      ],
    );
    await pump(tester);
    expect(find.text('Book first'), findsOneWidget);
    expect(find.text('Book second'), findsNothing);
    expect(find.text('Book completion'), findsNothing);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('42s'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Book latest')).dy, lessThan(tester.getTopLeft(find.text('Book first')).dy));
  });

  testWidgets('history refreshes for saved and reversed entries', (tester) async {
    await pump(tester);
    expect(find.text('No saved sessions yet.'), findsOneWidget);
    await store.commitTracking(activities: [entry('saved')]);
    await tester.pump();
    expect(find.text('Book saved'), findsOneWidget);
    expect(find.text('No saved sessions yet.'), findsNothing);
    await store.commitTracking(
      activities: [entry('reversal', kind: 'reversal', correctionOf: 'saved')],
    );
    await tester.pump();
    expect(find.text('Book saved'), findsNothing);
    expect(find.text('No saved sessions yet.'), findsOneWidget);
  });

  testWidgets('history limits older sessions and supports narrow large text', (tester) async {
    await store.commitTracking(activities: [for (var index = 0; index < 10; index++) entry('$index', minute: index)]);
    await pump(tester, width: 320, scale: 2);
    expect(find.text('Book 9'), findsOneWidget);
    expect(find.text('Book 2'), findsOneWidget);
    expect(find.text('Book 1'), findsNothing);
    expect(find.text('Book 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
