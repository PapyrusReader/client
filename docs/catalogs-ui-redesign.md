# Catalogs UI redesign

Catalogs now uses the library's page gutters, shared search field, grid-density rules, typography, and theme surfaces. Sources and navigation links are flat rows. Publication grids retain distinct editions and show covers, authors, and format descriptions without elevated card wrappers.

Book details are full pages at `/library/catalogs/:catalogId/book?feed=…&publication=…&q=…`. The source-feed URL and publication identifier are encoded query values; credentials are never included. In-memory metadata provides a quick preview, while direct navigation resolves the source feed and its publication document. Missing publications and catalog-store failures expose retry and return navigation. Returning preserves the source feed's position and view mode.

The main book action opens a format-selection sheet. Catalog forms, removal confirmation, and transfer activity also use bottom sheets. The Downloads header control replaces the persistent bottom bar and displays activity and failure indicators. Jobs continue after sheet dismissal and page navigation, preserve cancellation restrictions during commit, and link completed imports to their library book.

Catalog sheets follow the Import books styling: a left-aligned title and top-right close icon, a divider below the header, and a fixed footer with a top divider for actions. Content scrolls independently above the keyboard. Save, Cancel, and Remove stay in the footer; per-format and per-download actions stay with their corresponding items. Both close controls are disabled while a catalog is saving.

The existing relay, import pipeline, account isolation, and application-level job reset on catalog-setting changes remain in place. No backend API, database, or global theme changes are required.

## Verification and visual review

Verified on 2026-09-22:

- 485 OPDS, routing, library, search, book-detail, and shared-header regression tests passed. Ten opt-in network-fixture tests were skipped; the relay transport was not changed by this redesign.
- 39 catalog-page, presentation, and sheet tests passed in Chrome.
- Flutter analysis passed with no issues; the production web build passed.
- All 18 responsive/theme journeys passed and generated review screenshots, including enlarged text and keyboard insets. The shared library grid now uses its available content width so sidebar space cannot produce overly dense cards.
- Formatting and Git whitespace checks passed. Changes remain in the existing feature-branch working tree; nothing was deployed.

Regression coverage includes encoded deep links, detail resolution, edition identity, return navigation, stale sheets after account/catalog changes, storage-error recovery, grid/list switching, removal failures, keyboard-safe forms, progress/cancel/retry/commit behavior, and reduced motion.

The layout journey renders the actual app shell at 360, 600, 840, 1280, and 2507 logical pixels, in light, dark, and e-ink themes, plus 360px at twice the normal text size. It checks source lists, feeds, details, format sheets, transfer sheets, and the editor with an open keyboard. Screenshots use fixture data and existing repository cover artwork, not live catalog metadata.

Generate review images in `app/build/catalog-review`:

```sh
cd app
flutter test --no-pub test/opds/layout_test.dart \
  --dart-define=CAPTURE_OPDS=true \
  --dart-define=FLUTTER_FONT_DIR="$FLUTTER_ROOT/bin/cache/artifacts/material_fonts"
```

The font directory is optional for layout assertions. For screenshots it replaces Flutter's test-only Ahem fallback with the platform font. Desktop reference images render the existing library book header and grid for comparison.

- [Desktop catalog feed](../app/build/catalog-review/dark-1280-1x-feed.png)
- [Desktop book details](../app/build/catalog-review/dark-1280-1x-details.png)
- [Mobile download options](../app/build/catalog-review/light-360-1x-formats.png)
- [Wide catalog sources](../app/build/catalog-review/dark-2507-1x-sources.png)

Review images are generated build artifacts and are not committed.

## Mobile spacing refinement

The catalog browsing header keeps Back, the catalog name, Downloads, and settings together, above a full-width divider matching Edit book. The redundant Catalog home action and hostname subtitle have been removed. Search submission sits inside the search field, and a single grid/list switch shares the feed-heading row with refresh.

The feed heading and its controls stay below search while entries scroll. Refresh replaces only the content area with loading or error feedback; the heading stays visible through retry. A single grid/list icon button is used at every screen size.

On first load, the heading waits for the actual feed title. Link labels and placeholder titles are not used, so the title does not change when metadata arrives. Changing feeds or accounts clears the previous section's heading; refreshing the current feed keeps its loaded heading visible.

Book covers keep a fixed 2:3 ratio. Titles use their natural height, authors follow immediately, and edition captions can occupy two lines. This removes the empty title slot and makes similar editions easier to distinguish.

The visual fixture now also reproduces a two-edition feed with the long Pride and Prejudice heading and format labels, including the reported 424px screen width. [Updated mobile preview](../app/build/catalog-review/dark-424-1x-editions.png).

Follow-up verification: 224 targeted regression tests passed (ten opt-in network tests skipped), 41 Chrome tests passed, and 21 responsive/theme capture journeys passed. Analysis and the production web build also passed.

## Mobile catalog creation

Below the library's 840px desktop breakpoint, Add catalog uses the same floating action button as Add book. Downloads stays beside the page heading, removing the separate actions row. The source list includes bottom clearance so its last menu can scroll above the floating button. Desktop keeps its existing header action.

The Catalogs source page and catalog book details use the same header height, padding, title weight, and full-width divider as catalog browsing, without a subtitle. Book details keep Back and Downloads in the header, with compact Downloads on mobile.

Verification: 19 catalog-page tests passed in Chrome, including creation through the FAB and scrolling the last source menu clear of it. The 21 responsive/theme capture journeys check button placement above bottom navigation, desktop actions, and enlarged text. Flutter analysis passed. [Updated mobile sources](../app/build/catalog-review/dark-424-1x-sources.png).
