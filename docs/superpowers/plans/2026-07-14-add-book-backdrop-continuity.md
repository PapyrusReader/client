# Add Book Backdrop Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the add-book modal backdrop mounted while transitioning from the choice sheet to the digital import UI.

**Architecture:** Make the choice sheet own a small presentation state that swaps its body from the choice options to a reusable `ImportBookSheet` widget. Keep `ImportBookSheet.show` as the direct-entry modal wrapper, but move its scrollable content into `ImportBookSheet.build` so both entry paths share the same stateful import implementation.

**Tech Stack:** Flutter, Dart, Material modal bottom sheets, Flutter widget tests

---

### Task 1: Capture modal-backdrop continuity

**Files:**
- Modify: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Add a navigator observer and failing regression test**

Add a `_CountingNavigatorObserver` that increments `pushCount` in `didPush`. Extend `pumpLauncher` with an optional `navigatorObservers` argument and pass it to `MaterialApp`.

Add this test:

```dart
testWidgets('digital import transition preserves the modal backdrop', (tester) async {
  final observer = _CountingNavigatorObserver();
  await pumpLauncher(
    tester,
    (context) => () => AddBookChoiceSheet.show(context),
    navigatorObservers: [observer],
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  final initialPushCount = observer.pushCount;
  final initialBarrier = tester.element(find.byType(ModalBarrier));

  await tester.tap(find.text('Import digital books'));
  await tester.pumpAndSettle();

  expect(find.text('Import book'), findsOneWidget);
  expect(find.byType(ModalBarrier), findsOneWidget);
  expect(tester.element(find.byType(ModalBarrier)), same(initialBarrier));
  expect(observer.pushCount, initialPushCount);
});
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "digital import transition preserves the modal backdrop"
```

Expected: FAIL because the current callback pops the choice route and pushes a second modal route, changing the barrier element and incrementing `pushCount`.

### Task 2: Reuse import content within the choice route

**Files:**
- Modify: `app/lib/widgets/add_book/add_book_choice_sheet.dart`
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart`
- Test: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Make `ImportBookSheet` render its reusable content**

Change the direct modal builder to `const ImportBookSheet()` and implement `build` as:

```dart
@override
Widget build(BuildContext context) {
  return const SingleChildScrollView(child: _ImportContent());
}
```

- [x] **Step 2: Keep the choice modal route and swap its content**

Convert `AddBookChoiceSheet` to a `StatefulWidget`. Move the choice padding into the choice-state branch so the import content retains its existing layout. Store a `_showImport` boolean and change the digital option callback to `setState(() => _showImport = true)`.

The state build method begins with:

```dart
@override
Widget build(BuildContext context) {
  if (_showImport) {
    return const ImportBookSheet();
  }

  return Padding(
    padding: const EdgeInsets.only(
      left: Spacing.lg,
      right: Spacing.lg,
      top: Spacing.md,
      bottom: Spacing.lg,
    ),
    child: _buildChoices(context),
  );
}
```

Keep the physical-book callback unchanged: it still pops the choice route and opens `AddPhysicalBookSheet` with `callerContext`.

- [x] **Step 3: Format and run the focused test to verify GREEN**

Run:

```bash
dart format app/lib/widgets/add_book/add_book_choice_sheet.dart app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "digital import transition preserves the modal backdrop"
```

Expected: PASS.

- [x] **Step 4: Run complete focused verification**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart
flutter analyze lib/widgets/add_book/add_book_choice_sheet.dart lib/widgets/add_book/import_book_sheet.dart test/widgets/add_book/add_book_sheets_test.dart
```

Expected: all add-book sheet tests pass and analysis reports `No issues found!`.

- [x] **Step 5: Commit the implementation**

```bash
git add app/lib/widgets/add_book/add_book_choice_sheet.dart app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart docs/superpowers/plans/2026-07-14-add-book-backdrop-continuity.md
git commit -m "fix: preserve add book modal backdrop"
```
