# Book Edit Responsive Pane Design

## Goal

Use desktop space efficiently on the book edit page without allowing the cover pane or form fields to become cramped. Preserve the existing cover editing workflow and mobile layout.

## Layout

The desktop edit body uses the width allocated by its parent, excluding the application sidebar.

- When the available content width can accommodate a 280 px supporting pane, the standard pane gap, page padding, and at least 420 px for the form, show the cover pane and form side by side.
- The cover pane has a fixed width of 280 px. The cover preview remains constrained and does not grow with the page.
- The form pane is flexible and consumes the remaining width, up to the page's existing maximum width.
- When less space is available, stack the cover pane above the form while retaining desktop-sized cover constraints. Do not switch to the mobile full-width cover merely because the panes stack.

The breakpoint is derived from these minimum pane dimensions and evaluated with `LayoutBuilder`, rather than from the full browser width.

## Form Rows

Rows containing two optional fields respond to the width of the form pane itself:

- Display fields side by side when both receive a usable input width.
- Stack fields vertically when the form pane is too narrow.

This behavior prevents field truncation while allowing the page-level panes to remain side by side at intermediate desktop widths.

## Unchanged Behavior

- Cover upload, URL entry, removal, preview, and persistence are unchanged.
- Metadata lookup behavior is unchanged.
- Form validation, saving, routing, and unsaved-change handling are unchanged.
- The existing mobile page layout is unchanged.
- The desktop header and Save action remain unchanged.

## Verification

Widget tests cover three states:

1. Wide desktop: cover and form panes are side by side.
2. Intermediate desktop: panes remain side by side while paired form fields stack as necessary, with no render overflow.
3. Constrained desktop: cover pane stacks above the form and the cover preview stays compact.

Static analysis must report no issues in the changed files.
