# Book Edit Layout Alignment Implementation Plan

**Goal:** Make the book edit page read as the edit state of the book details page by sharing its left content origin, adding persistent page actions, and preserving the existing responsive form behavior.

**Architecture:** Keep `BookEditPage` and `BookEditProvider` behavior intact. Restructure only the page composition: a fixed desktop header above a left-aligned, width-constrained scroll area; retain the existing mobile app bar and stacked form. Add widget tests around visible controls and relative geometry rather than implementation-specific widget nesting.

**Tech Stack:** Flutter, Material, Provider, `flutter_test`

---

### Task 1: Add responsive layout regression tests

**Files:**
- Create: `app/test/pages/book_edit_page_layout_test.dart`
- Reference: `app/test/helpers/test_helpers.dart`
- Reference: `app/lib/pages/book_edit_page.dart`

1. Add a desktop test that loads a real test book and verifies the page title, Back action, and Save action.
2. Verify the desktop content begins at the normal page margin instead of being horizontally centered.
3. Verify the cover and fields are side by side and Save is outside the scrolling form content.
4. Add a narrow-screen test verifying the cover section precedes the form fields with no horizontal overflow.
5. Run the test and confirm the desktop assertions fail against the current centered layout.

### Task 2: Restructure the edit page layout

**Files:**
- Modify: `app/lib/pages/book_edit_page.dart`

1. Add a compact desktop page header with a back arrow, `Edit book`, and a text-only primary Save action.
2. Keep the header outside the scroll area so Save remains available on long forms.
3. Replace the centered desktop wrapper with a top-left-aligned container using the same desktop page margin as book details.
4. Preserve the two-column form, using a cover column close to the details-page cover position and a constrained overall width.
5. Remove the disconnected bottom Save button.
6. Preserve the current mobile app bar and stacked form behavior, adding stable semantic labels/keys where needed by the regression tests.

### Task 3: Verify behavior and quality

**Files:**
- Test: `app/test/pages/book_edit_page_layout_test.dart`
- Test: existing book edit and provider tests

1. Format changed Dart files.
2. Run the focused layout test.
3. Run existing book edit/provider tests that cover form and cover behavior.
4. Run Flutter analysis for the changed files or application package.
5. Review the final diff to confirm no form data, validation, or persistence behavior changed.
