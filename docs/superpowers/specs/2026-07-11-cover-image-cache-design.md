# Stable Local Cover Image Cache Design

- Status: Approved design
- Date: 2026-07-11
- Audience: Papyrus client engineers

## Overview

Papyrus persists private cover bytes in filesystem storage or browser OPFS. A newly mounted `PrivateBookCover` currently reads those bytes asynchronously and renders its placeholder until the read completes. Navigating between the library, book details, shelves, and list layouts therefore produces a visible cover flash even when the cover was already displayed moments earlier.

This design gives each local cover a stable Flutter image-provider identity. Flutter's bounded least-recently-used `ImageCache` can then reuse the decoded image across widget instances and page transitions, while filesystem storage remains authoritative across app restarts.

## Goals

- Keep a previously displayed cover visually stable across page and layout transitions.
- Reuse Flutter's existing bounded decoded-image cache instead of adding an unbounded byte cache.
- Support account cached covers, account pending covers, and permanent guest covers.
- Preserve the existing local-first and cross-device storage behavior.
- Keep the first load and error behavior deterministic and testable.

## Non-goals

- Persist decoded images outside the current app session.
- Replace OPFS or native filesystem cover storage.
- Change server media endpoints, PowerSync schemas, or media synchronization.
- Preload every cover in a large library.
- Resize or recompress imported covers in this change.

## Constraints

- Cover bytes must not be stored in SQL, PowerSync rows, or `SharedPreferences`.
- Cache keys must include the server/account scope so private covers cannot cross profiles or users.
- Guest covers must remain isolated from authenticated libraries.
- A replaced cover must receive a different key or explicitly evict the previous key.
- Book removal and local-cache clearing must evict the associated decoded image where practical; stale entries remain bounded by Flutter's LRU limit if an explicit key is unavailable.

## Proposed design

### Stable provider

Add a filesystem-backed `ImageProvider` for private covers. Its immutable key contains:

- storage scope persistence key;
- cover bucket (`cached`, `pending`, or guest `books`);
- file identifier (media ID or book ID).

The provider loads encoded bytes through the existing `BookImportService` APIs and decodes them through Flutter's image pipeline. Equal provider keys resolve through the same `ImageStreamCompleter`, allowing Flutter's global `ImageCache` to reuse decoded pixels across newly mounted widgets.

Public HTTP covers continue using `CachedNetworkImage`; inline legacy data URIs keep their compatibility path.

### Rendering

`PrivateBookCover` chooses one provider in the existing priority order:

1. public or legacy inline cover;
2. authenticated cached cover by media ID;
3. authenticated pending cover by book ID;
4. guest permanent cover by book ID.

For filesystem-backed covers, the widget layers the placeholder behind `Image(image: provider)`. The placeholder is visible only until the first successful decode. If the same provider key was already decoded, the cached image stream supplies the frame without another filesystem read or placeholder transition.

### Cache ownership and limits

Papyrus does not add a second raw-byte LRU. Flutter's `ImageCache` remains the session-memory owner and uses its configured LRU entry and byte limits. OPFS or native filesystem storage remains the persistent cache and offline source of truth.

### Invalidation

- Promotion changes identity from `pending/<book-id>` to `cached/<media-id>`; the already rendered frame remains visible while the new provider resolves.
- Replacing a cover produces a new media ID and therefore a new cache key.
- Switching server profile, account, or guest mode changes the scope component and cannot reuse another library's private image.
- Deleting a book or clearing local authenticated cover files evicts known provider keys when the caller has them. Flutter's LRU bounds any unreachable decoded entry that cannot be targeted directly.

## Failure behavior

- Missing local bytes produce the existing placeholder.
- A cached account cover that is absent locally continues through `MediaCacheService.ensureCoverCached`, which performs the authenticated lazy download and writes the result to local storage.
- Decode and filesystem errors remain local to the cover widget and do not break the surrounding library page.
- A failed replacement does not evict a previously decoded provider until the new provider has produced a frame.

## Testing

- Two separately mounted widgets with the same provider key invoke the filesystem loader once.
- Navigating from a library cover to a details cover with the same key reuses the cached image stream.
- Different account scopes and storage buckets do not share cache entries.
- Media-ID replacement uses a new provider key.
- Missing bytes and decode failures render the placeholder.
- Existing pending, guest, authenticated lazy-download, profile-switch, and metadata-regression tests remain green.

## Rollout and rollback

The change is client-only and requires no data migration. Rollout consists of the provider implementation, `PrivateBookCover` integration, focused widget tests, and a browser navigation smoke test. Rollback restores the existing `FutureBuilder<Uint8List?>` renderer; persisted cover files and synchronized metadata remain compatible.

## Open questions

None for this iteration. Cover thumbnail generation and image-size optimization can be evaluated separately if profiling shows decode memory pressure.
