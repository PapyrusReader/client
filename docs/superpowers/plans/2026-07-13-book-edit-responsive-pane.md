# Book Edit Responsive Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the cover and edit form side by side at useful intermediate desktop widths while preventing narrow form fields and oversized stacked covers.

**Architecture:** `BookEditPage` will use its parent constraints and minimum pane dimensions to choose between a supporting-pane row and a stacked desktop layout. `ResponsiveFormRow` will independently use its own constraints to stack paired inputs when the flexible form pane is narrow.

**Tech Stack:** Flutter, Dart, Material widgets, `LayoutBuilder`, Flutter widget tests

---

### Task 1: Capture intermediate and constrained desktop behavior

**Files:**
- Modify: `app/test/pages/book_edit_page_layout_test.dart`

- [ ] **Step 1: Replace the constrained-desktop test and add the intermediate case**

Use an 800 px content allocation to assert that the cover and form remain side by side while Publisher and Language stack inside the narrower form pane. Use a 760 px allocation to assert that the page panes stack and the cover preview remains 240 px wide.

```dart
testWidgets('intermediate desktop keeps panes side by side while paired fields stack', (tester) async {
  await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 800);

  final coverHeading = tester.getTopLeft(find.text('Cover'));
  final formHeading = tester.getTopLeft(find.text('Basic information'));
  final publisher = tester.getTopLeft(find.text('Publisher'));
  final language = tester.getTopLeft(find.text('Language'));

  expect(formHeading.dx, greaterThan(coverHeading.dx));
  expect((formHeading.dy - coverHeading.dy).abs(), lessThan(4));
  expect(language.dy, greaterThan(publisher.dy));
  expect(tester.takeException(), isNull);
});

testWidgets('constrained desktop stacks panes and keeps the cover compact', (tester) async {
  await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 760);

  final coverHeading = tester.getTopLeft(find.text('Cover'));
  final formHeading = tester.getTopLeft(find.text('Basic information'));

  expect(formHeading.dy, greaterThan(coverHeading.dy));
  expect(tester.getSize(find.byType(AspectRatio).first).width, 240);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run the focused tests and verify the intermediate case fails**

Run:

```bash
cd app
flutter test test/pages/book_edit_page_layout_test.dart
```

Expected: the 800 px case fails because the current 840 px page breakpoint stacks the cover above the form.

### Task 2: Make page panes respond to usable minimum widths

**Files:**
- Modify: `app/lib/pages/book_edit_page.dart`

- [ ] **Step 1: Derive the pane breakpoint from layout dimensions**

Add constants to `_BookEditPageState` and use them in `_buildDesktopLayout` and `_buildDesktopCoverPane`:

```dart
static const double _desktopCoverPaneWidth = 280;
static const double _minimumDesktopFormPaneWidth = 420;
static const double _desktopPaneBreakpoint =
    _desktopCoverPaneWidth + Spacing.xl + _minimumDesktopFormPaneWidth + (Spacing.lg * 2);
```

Replace the generic desktop breakpoint check:

```dart
final showSideBySide = constraints.maxWidth >= _desktopPaneBreakpoint;
```

Set the cover pane width from the shared dimension:

```dart
return SizedBox(
  width: _desktopCoverPaneWidth,
  child: Column(...),
);
```

- [ ] **Step 2: Run the layout tests**

Run:

```bash
cd app
flutter test test/pages/book_edit_page_layout_test.dart
```

Expected: the page-level position assertions pass; the intermediate paired-field assertion still fails because `ResponsiveFormRow` uses the browser-level desktop flag.

### Task 3: Make paired form fields respond to their allocated width

**Files:**
- Modify: `app/lib/widgets/book_form/responsive_form_row.dart`
- Test: `app/test/pages/book_edit_page_layout_test.dart`

- [ ] **Step 1: Use local constraints for the horizontal row decision**

Keep `isDesktop` as the mobile/desktop policy input, but use `LayoutBuilder` to require at least the existing tablet breakpoint before placing multiple fields side by side:

```dart
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final showAsRow =
          isDesktop && children.length > 1 && constraints.maxWidth >= Breakpoints.tablet;

      if (!showAsRow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children.expand((widget) sync* {
            yield widget;
            yield const SizedBox(height: Spacing.md);
          }).toList()
            ..removeLast(),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.expand((widget) sync* {
          yield Expanded(child: widget);
          yield const SizedBox(width: Spacing.md);
        }).toList()
          ..removeLast(),
      );
    },
  );
}
```

- [ ] **Step 2: Format and run the complete layout test file**

Run:

```bash
dart format app/lib/pages/book_edit_page.dart app/lib/widgets/book_form/responsive_form_row.dart app/test/pages/book_edit_page_layout_test.dart
cd app
flutter test test/pages/book_edit_page_layout_test.dart
```

Expected: all book edit layout tests pass with no render-overflow exceptions.

- [ ] **Step 3: Run static analysis**

Run:

```bash
cd app
flutter analyze lib/pages/book_edit_page.dart lib/widgets/book_form/responsive_form_row.dart test/pages/book_edit_page_layout_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit the implementation**

```bash
git add app/lib/pages/book_edit_page.dart app/lib/widgets/book_form/responsive_form_row.dart app/test/pages/book_edit_page_layout_test.dart docs/superpowers/plans/2026-07-13-book-edit-responsive-pane.md
git commit -m "fix: improve responsive book edit layout"
```
