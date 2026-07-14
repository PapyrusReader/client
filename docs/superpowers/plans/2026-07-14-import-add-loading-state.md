# Import Add-to-Library Loading State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the add-to-library button color pulse with a stable, accessible `Adding...` loading state.

**Architecture:** Extend the existing test-only successful-import constructor so widget tests can render the real committing state. Keep both buttons disabled during the commit, override only their disabled colors to match their active visuals, show progress inside the primary action, and avoid resetting the successful commit state before dismissing the sheet.

**Tech Stack:** Flutter, Dart, Material buttons, Flutter widget tests

---

### Task 1: Render the committing success state in tests

**Files:**
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart:25-75`
- Modify: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Add a failing committing-state test**

Add a widget test that pumps:

```dart
MaterialApp(
  theme: AppTheme.dark,
  home: const Scaffold(
    body: ImportBookSheet.withInitialResult(
      importedBook,
      initialCommitting: true,
    ),
  ),
)
```

Read the `Pick different file` and primary filled buttons, then expect both `onPressed` callbacks to be null.

- [x] **Step 2: Run the test to verify RED**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "committing import actions stay visually stable and show progress"
```

Expected: FAIL to compile because `initialCommitting` is not defined.

- [x] **Step 3: Add the minimal initial-committing test seam**

Give `ImportBookSheet`, `_ImportContent`, and `_ImportContentState` an initial committing value:

```dart
const ImportBookSheet({super.key})
  : initialResult = null,
    initialCommitting = false;

@visibleForTesting
const ImportBookSheet.withInitialResult(
  this.initialResult, {
  this.initialCommitting = false,
  super.key,
});

final bool initialCommitting;
```

Pass the value into `_ImportContent`, declare `_committing` as `late`, and assign `widget.initialCommitting` in `initState`.

- [x] **Step 4: Run the test to verify the seam is GREEN**

Run the command from Step 2.

Expected: PASS for the disabled-callback assertions.

### Task 2: Keep colors stable and show progress

**Files:**
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart:153-215, 349-375`
- Modify: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [x] **Step 1: Add failing loading-content and disabled-color assertions**

Extend the committing-state test:

```dart
expect(find.text('Adding...'), findsOneWidget);
expect(find.text('Add to library'), findsNothing);
expect(find.byType(CircularProgressIndicator), findsOneWidget);

final colorScheme = Theme.of(tester.element(find.text('Adding...'))).colorScheme;
const disabled = {WidgetState.disabled};

expect(pickButton.style?.foregroundColor?.resolve(disabled), colorScheme.primary);
expect(pickButton.style?.side?.resolve(disabled)?.color, colorScheme.outline);
expect(addButton.style?.backgroundColor?.resolve(disabled), colorScheme.primary);
expect(addButton.style?.foregroundColor?.resolve(disabled), colorScheme.onPrimary);
```

- [x] **Step 2: Run the test to verify RED**

Run the command from Task 1, Step 2.

Expected: FAIL because the primary button still displays `Add to library` and the explicit disabled colors are absent.

- [x] **Step 3: Implement the stable loading visuals**

Use the success state's `colorScheme` to add:

```dart
disabledForegroundColor: colorScheme.primary,
side: BorderSide(color: colorScheme.outline, width: BorderWidths.thin),
```

to the outlined button style, and:

```dart
disabledBackgroundColor: colorScheme.primary,
disabledForegroundColor: colorScheme.onPrimary,
```

to the filled button style.

When `_committing` is true, replace the primary label with:

```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: colorScheme.onPrimary,
      ),
    ),
    const SizedBox(width: Spacing.sm),
    const Text('Adding...'),
  ],
)
```

- [x] **Step 4: Preserve the loading state until successful dismissal**

Reset `_committing` inside the error handler together with the error state. Remove the unconditional successful reset from `finally`, so a successful commit dismisses the modal while still showing `Adding...`.

- [x] **Step 5: Format and verify GREEN**

Run:

```bash
dart format app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "committing import actions stay visually stable and show progress"
```

Expected: PASS.

- [x] **Step 6: Run complete focused verification**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart
flutter analyze lib/widgets/add_book/import_book_sheet.dart test/widgets/add_book/add_book_sheets_test.dart
```

Expected: all add-book sheet tests pass and analysis reports `No issues found!`.

- [x] **Step 7: Commit the implementation**

```bash
git add app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart docs/superpowers/plans/2026-07-14-import-add-loading-state.md
git commit -m "fix: stabilize import commit loading state"
```
