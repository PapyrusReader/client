# Add Book Backdrop Continuity Design

## Goal

Prevent the modal backdrop from flashing when the add-book choice sheet transitions to the digital-book import sheet.

## Root Cause

The digital option currently pops the add-book choice `ModalBottomSheetRoute` and immediately pushes a new import `ModalBottomSheetRoute`. Each route owns a separate `ModalBarrier`, so the backdrop is removed and recreated while the two route animations overlap. The visible flash is a route-lifecycle artifact, not an import-content rendering issue.

## Design

Keep the existing add-book modal route mounted when the user selects **Import digital books**. The choice sheet will switch its body to the existing import content inside that route, preserving the same barrier and navigator overlay entry throughout the transition.

`ImportBookSheet.show` will remain available for callers that open the import flow directly. Its content widget will be reusable by the choice sheet so import behavior, state, file handling, and layout stay in one implementation.

The **Add physical book** path remains unchanged because it does not exhibit the reported flash and changing its large draggable form would expand the scope.

## Transition Behavior

- Opening **Add book** creates one modal route and one backdrop.
- Selecting **Import digital books** replaces only the sheet content; it does not pop or push a route.
- Canceling or dismissing the import content closes the existing modal route and returns to the library, matching current behavior.
- Direct calls to `ImportBookSheet.show` continue to open the same import UI in a modal bottom sheet.

## Verification

Add a widget regression test that opens the choice sheet, records the active modal barrier, selects **Import digital books**, and verifies:

- the import content is displayed;
- exactly one modal barrier remains;
- the original barrier element remains mounted, proving it was not recreated;
- no additional popup route is pushed during the content transition.

Run the focused add-book widget tests and static analysis for the modified files.
