# OPDS library recognition and caching implementation plan

**Goal:** Recognize previously imported catalog publications after restart and show previously visited feeds immediately, including when offline.

**Architecture:** Keep local provenance and a bounded resource cache alongside the existing scoped catalog preferences. Match catalog identity plus exact publication ID and acquisition URL, never title or ISBN. Validate recorded local book IDs against the currently loaded DataStore. Cache raw feed responses (preserving redirect bases) and artwork, without authentication headers or credentials. Render cached feeds while refreshing through the existing relay.

**Tech stack:** Flutter, ChangeNotifier, SharedPreferences, existing OPDS parsers and import sessions; no backend/schema changes.

## Decisions

- Anonymous and authenticated libraries use the existing catalog persistence scope; no cross-account matches or cached responses.
- Only successful imports record provenance; completion after an account switch cannot modify the active library's state.
- Publication-level recognition provides Open book; format options match their exact acquisition URL so additional formats remain downloadable.
- Deleting a book makes its provenance non-matching. Do not remove mappings merely because the library is still loading.
- Catalog URL/credential changes invalidate affected cache entries and outstanding writes. Removing a catalog removes its cached data. Name-only edits preserve import recognition.
- Feed/cache storage is bounded and evicts older entries. Corruption or quota errors must never prevent browsing or imports.
- Cache reads retain the final response URI so relative links resolve identically online and offline. Book binaries are never cached here.
- Refresh errors preserve available content with an explicit cached-content notice and retry. Authentication failures invalidate the affected cached content rather than silently presenting it as current.
- No title-based backfill for earlier imports: they lack reliable provenance. Recognition starts with imports made after this change.

## Task 1 — Persistent import recognition

- [x] Add `app/lib/opds/opds_library.dart`: scoped persisted exact identities, read only when the referenced book exists in DataStore, change notifications for live deletion/import updates.
- [x] Update `app/lib/opds/opds_downloads.dart`: capture provenance destination at import start; record only after commit; prevent repeated imports of an already-owned acquisition.
- [x] Wire lifecycle in `app/lib/main.dart` and invalidation in `app/lib/opds/opds_catalogs.dart`.
- [x] Update publication tiles, details and download options to display In library / Open book, preserving access to other formats.
- [x] Test persistence, deletion, failed import, concurrent imports, scope changes, URL changes and distinct editions in OPDS unit/widget tests.

## Task 2 — Bounded feed and cover cache

- [x] Add `app/lib/opds/opds_resource_cache.dart`: bounded persistent response storage; scoped keys; invalidation generation; corruption/quota recovery; content-type-only header persistence.
- [x] Update `app/lib/opds/opds_browser.dart`: render cached data before network completion, revalidate, retain it on connection failures, and reject late results after navigation/scope changes.
- [x] Integrate cache into catalog pages/details and covers without caching book downloads.
- [x] Test warm and cold reads, background replacement, offline reuse, eviction, redirect-relative URLs, corrupt storage, auth failure, and invalidation races.

## Task 3 — Integration and verification

- [x] Add widget coverage for In library / Open book, deletion, cached-content notices and refresh behavior.
- [x] Update `docs/opds-support.md` with local-only storage, limits, and recognition limitations.
- [x] Run `flutter analyze --no-pub`, OPDS tests, shell/routing/library tests relevant to the modified lifecycle, and the web bootstrap tests.
- [x] Inspect changes and `git diff --check`; report results and any remaining limitations. Leave changes reviewable in the working tree.

## Verification

- Flutter analysis: no issues.
- OPDS, routing, shell, import-session/commit and library-page tests: 278 passed, 10 skipped.
- Web bootstrap tests: 4 passed.
- Production web build passed (including the Wasm compatibility dry run).
- Responsive layout journeys include light/dark/e-ink, mobile/tablet/desktop/wide and enlarged text; captures exercise owned details, per-format ownership, and offline cached feeds.
- Review regressions cover invalid optional artwork and both authorization-response orderings across retained parent feeds and details pages.
