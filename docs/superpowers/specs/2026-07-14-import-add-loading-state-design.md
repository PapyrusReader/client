# Import Add-to-Library Loading State Design

## Goal

Remove the distracting button-color pulse when a successfully imported digital book is added to the library, while providing clear progress feedback.

## Root Cause

Pressing **Add to library** sets `_committing` to true, which disables both actions and animates them into Material's disabled colors. The current `finally` block sets `_committing` back to false immediately before a successful sheet dismissal, so the buttons briefly animate toward their enabled colors again. The two state changes create the visible pulse.

## Design

During a commit:

- Both actions remain disabled so duplicate commits and file changes are impossible.
- The outlined secondary action retains its normal foreground and border colors.
- The filled primary action retains its normal background and foreground colors.
- The primary button replaces `Add to library` with a compact progress indicator and the label `Adding...`.
- Button size, pill shape, spacing, and row layout remain unchanged.

On success, `_committing` remains true until the modal sheet closes. This prevents the loading content from switching back before dismissal. On failure, `_committing` resets and the existing error state remains responsible for communicating the failure and retry action.

## Accessibility

Both buttons use `onPressed: null` during the commit, preserving correct disabled semantics for assistive technology. Progress is communicated with visible text as well as an indeterminate indicator, so it does not rely on color or animation alone.

## Verification

Extend the existing successful-import widget-test seam with an initial committing state. Verify that:

- both action callbacks are disabled;
- the primary action shows `Adding...` and a progress indicator;
- the primary disabled colors resolve to the active primary colors;
- the secondary disabled foreground and border resolve to their active visual colors;
- `Add to library` is not displayed during the commit.

Run the focused add-book sheet tests and static analysis for the modified files.
