# Add Book Bottom Sheets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present the add-book choice and digital import flows as content-sized bottom sheets on every screen and show the requested digital format list.

**Architecture:** Remove desktop dialog branches from both sheet entry points and use the existing modal bottom-sheet components consistently. Keep import behavior unchanged; only presentation and explanatory copy change.

**Tech Stack:** Flutter, Dart, Material modal bottom sheets, Flutter widget tests

---

### Task 1: Capture desktop bottom-sheet behavior

**Files:**
- Create: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [ ] **Step 1: Add a desktop test harness and failing choice-sheet test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/add_book/add_book_choice_sheet.dart';
import 'package:papyrus/widgets/add_book/import_book_sheet.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';

void main() {
  Future<void> pumpLauncher(WidgetTester tester, VoidCallback Function(BuildContext) action) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(onPressed: action(context), child: const Text('Open')),
          ),
        ),
      ),
    );
  }

  testWidgets('add book opens as a bottom sheet on desktop', (tester) async {
    await pumpLauncher(tester, (context) => () => AddBookChoiceSheet.show(context));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheetHandle), findsOneWidget);
    expect(find.text('EPUB, PDF, AZW3, MOBI, CBZ/CBR'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Add the failing import-sheet test**

```dart
testWidgets('import book opens as a format-neutral bottom sheet on desktop', (tester) async {
  await pumpLauncher(tester, (context) => () => ImportBookSheet.show(context));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.byType(Dialog), findsNothing);
  expect(find.byType(BottomSheetHandle), findsOneWidget);
  expect(find.text('Select a digital book file'), findsOneWidget);
  expect(find.text('EPUB, PDF, AZW3, MOBI, CBZ/CBR'), findsOneWidget);
  expect(find.text('Select an EPUB file'), findsNothing);
});
```

- [ ] **Step 3: Run the tests and verify both fail**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart
```

Expected: FAIL because desktop width currently opens `Dialog` widgets and the copy is EPUB-specific.

### Task 2: Convert the choice dialog to a bottom sheet

**Files:**
- Modify: `app/lib/widgets/add_book/add_book_choice_sheet.dart`
- Test: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [ ] **Step 1: Use one modal bottom-sheet entry point**

Replace the desktop/mobile branching in `AddBookChoiceSheet.show` with:

```dart
return showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
  ),
  builder: (_) => Padding(
    padding: const EdgeInsets.only(
      left: Spacing.lg,
      right: Spacing.lg,
      top: Spacing.md,
      bottom: Spacing.lg,
    ),
    child: AddBookChoiceSheet(callerContext: context),
  ),
);
```

Always render `BottomSheetHandle`, remove the unused `foundation.dart` import, and set the digital option subtitle to `EPUB, PDF, AZW3, MOBI, CBZ/CBR`.

- [ ] **Step 2: Run the focused choice-sheet test**

Run:

```bash
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart --plain-name "add book opens as a bottom sheet on desktop"
```

Expected: PASS.

### Task 3: Convert the import dialog to a content-sized bottom sheet

**Files:**
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart`
- Test: `app/test/widgets/add_book/add_book_sheets_test.dart`

- [ ] **Step 1: Replace dialog and draggable-sheet branches**

Use one scrollable, content-sized bottom sheet:

```dart
return showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
  ),
  builder: (_) => SingleChildScrollView(
    child: const Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.md,
        bottom: Spacing.lg,
      ),
      child: _ImportContent(),
    ),
  ),
);
```

Always render `BottomSheetHandle`. Change the idle title to `Select a digital book file` and add `EPUB, PDF, AZW3, MOBI, CBZ/CBR` before the unchanged offline-storage explanation. Do not change `_webExtensions`, `_nativeExtensions`, or `BookImportService`.

- [ ] **Step 2: Format and run focused verification**

Run:

```bash
dart format app/lib/widgets/add_book/add_book_choice_sheet.dart app/lib/widgets/add_book/import_book_sheet.dart app/test/widgets/add_book/add_book_sheets_test.dart
cd app
flutter test test/widgets/add_book/add_book_sheets_test.dart
flutter analyze lib/widgets/add_book/add_book_choice_sheet.dart lib/widgets/add_book/import_book_sheet.dart test/widgets/add_book/add_book_sheets_test.dart
```

Expected: both widget tests pass and analysis reports `No issues found!`.
