# Add Book Bottom Sheets Design

## Goal

Present both steps of the add-book flow as bottom sheets on every screen size and describe digital imports without emphasizing EPUB.

## Presentation

`AddBookChoiceSheet.show` and `ImportBookSheet.show` always use `showModalBottomSheet`. Remove their desktop-only dialog branches.

- Use the root navigator so follow-up sheets appear above the application shell.
- Use the existing rounded top corners and standard bottom-sheet handle.
- Respect safe areas.
- Keep the choice sheet content-sized.
- Keep the import sheet content-sized in its idle state and scrollable when processing results, errors, or metadata previews increase its height.
- Do not reserve a fixed fraction of the viewport when the content does not require it.

## Copy

The digital import option and idle import state use format-neutral language:

- Action: `Import digital books`
- Format list: `EPUB, PDF, AZW3, MOBI, CBZ/CBR`
- Prompt: `Select a digital book file`

The offline-storage explanation and `Browse files` action remain unchanged.

## Scope

This change does not expand browser import support. The web file picker and importer continue accepting only EPUB until multi-format browser processing is implemented. Native import behavior is unchanged.

## Verification

Widget tests verify that:

1. Both entry points use modal bottom sheets at desktop width.
2. Both sheets display the standard handle.
3. EPUB-specific prompts are absent.
4. The requested format list is visible.
5. The choice sheet still opens the import sheet and physical-book sheet correctly.
