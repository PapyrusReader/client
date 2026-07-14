# Import Action Button Shapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the successful digital-import action pair with matching pill-shaped buttons.

**Architecture:** Add a test-only initial-result constructor so the real import success UI can be rendered deterministically in a widget test. Then apply an explicit `StadiumBorder` to both success actions, keeping their hierarchy, layout, and callbacks unchanged.

**Tech Stack:** Flutter, Dart, Material buttons, Flutter widget tests

---

### Task 1: Make the real success state testable

**Files:**
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart:22-59`
- Modify: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Add a failing success-state rendering test**

Import `BookImportResult` and add this fixture:

```dart
const importedBook = BookImportResult(
  bookId: 'book-1',
  title: 'Frankenstein',
  author: 'Mary Wollstonecraft Shelley',
  pageCount: 239,
  fileSize: 1024,
  fileHash: 'hash',
  fileExtension: 'epub',
);
```

Add a widget test that pumps:

```dart
MaterialApp(
  home: Scaffold(
    body: ImportBookSheet.withInitialResult(importedBook),
  ),
)
```

and expects `Pick different file` and `Add to library` to be present.

- [x] **Step 2: Run the test to verify RED**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "successful import actions can be rendered for widget verification"
```

Expected: FAIL to compile because `ImportBookSheet.withInitialResult` does not exist.

- [x] **Step 3: Add the minimal test-only initial-result seam**

Add an `@visibleForTesting` named constructor and nullable `initialResult` field to `ImportBookSheet`. Pass it into `_ImportContent`, then initialize `_state` and `_result` in `initState`:

```dart
const ImportBookSheet({super.key}) : initialResult = null;

@visibleForTesting
const ImportBookSheet.withInitialResult(this.initialResult, {super.key});

final BookImportResult? initialResult;
```

```dart
@override
void initState() {
  super.initState();
  _result = widget.initialResult;
  _state = _result == null ? _ImportState.idle : _ImportState.success;
}
```

- [x] **Step 4: Run the rendering test to verify GREEN**

Run the command from Step 2.

Expected: PASS with both real success actions rendered.

### Task 2: Apply and verify matching pill shapes

**Files:**
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart:335-354`
- Modify: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Extend the success-state test with failing shape assertions**

Read both rendered button widgets and resolve their explicit shape styles:

```dart
final pickButton = tester.widget<OutlinedButton>(
  find.widgetWithText(OutlinedButton, 'Pick different file'),
);
final addButton = tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Add to library'),
);

expect(pickButton.style?.shape?.resolve({}), isA<StadiumBorder>());
expect(addButton.style?.shape?.resolve({}), isA<StadiumBorder>());
```

- [x] **Step 2: Run the test to verify RED**

Run the command from Task 1, Step 2.

Expected: FAIL because neither success action currently defines an explicit shape style.

- [x] **Step 3: Apply explicit pill styles to both buttons**

Add these local styles without changing any other properties:

```dart
style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
```

```dart
style: FilledButton.styleFrom(shape: const StadiumBorder()),
```

- [x] **Step 4: Format and verify GREEN**

Run:

```bash
dart format app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "successful import actions can be rendered for widget verification"
```

Expected: PASS.

- [x] **Step 5: Run complete focused verification**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart
flutter analyze lib/widgets/add_book/import_book_sheet.dart test/widgets/add_book/add_book_sheets_test.dart
```

Expected: all add-book sheet tests pass and analysis reports `No issues found!`.

- [x] **Step 6: Commit the implementation**

```bash
git add app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart docs/superpowers/plans/2026-07-14-import-action-button-shapes.md
git commit -m "fix: unify import action button shapes"
```
