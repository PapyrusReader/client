# Import Action Button Shapes Design

## Goal

Give the paired actions in the successful digital-book import state one consistent pill shape.

## Current Behavior

`Pick different file` is an `OutlinedButton` that inherits Papyrus's 8px rounded-rectangle shape. `Add to library` is a `FilledButton` that inherits Material 3's pill shape because the application theme does not define a filled-button shape. Their equal placement makes the mismatch visually prominent.

## Design

Apply an explicit `StadiumBorder` to both success-state buttons:

- `Pick different file` remains an outlined secondary action.
- `Add to library` remains a filled primary action.
- Both buttons retain their equal widths, current spacing, labels, enabled and disabled behavior, and callbacks.

The shape override is local to the successful import action row. It does not change global button themes or introduce a shared component.

## Verification

Extend the add-book sheet widget tests to render the successful import state and verify that the outlined and filled actions both resolve to `StadiumBorder`. Run the focused add-book sheet tests and static analysis for the modified files.
