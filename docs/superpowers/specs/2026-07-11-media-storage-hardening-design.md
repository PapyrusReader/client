# Media Storage Hardening Design

## Context

The media-storage pipeline spans the Papyrus Flutter client and FastAPI server. Book metadata is synchronized through PowerSync while book files and cover images remain private media assets stored outside the synchronized database.

Guest and account libraries are intentionally separate. Signing in does not migrate or merge guest books, files, covers, or pending work into an account library. This design preserves that boundary and hardens only authenticated media behavior.

## Goals

- Persist authenticated cover images in platform-local files after their first successful display.
- Render private covers consistently across every book-cover surface.
- Isolate pending uploads and cached covers by selected server and authenticated user.
- Ensure only one client upload-queue processor runs at a time.
- Start upload processing after new tasks have been durably enqueued.
- Prevent concurrent server uploads from creating duplicate assets or exceeding quota.
- Restore a passing client CI suite with the intended `Download` and `Delete` labels.

## Non-goals

- Migrating or merging guest libraries into account libraries.
- Proactively downloading all covers during metadata synchronization.
- Storing cover bytes in SQLite, PowerSync tables, PostgreSQL, or SharedPreferences.
- Adding cross-server media transfer.
- Redesigning the existing media API.

## Profile identity and isolation

Authenticated local media state is scoped by two values:

1. The selected sync-server profile key already produced by `SyncSettingsProvider.activeProfileKey`.
2. The authenticated server user ID.

Together they form an immutable media scope for one server/account pair. Upload tasks and cover-cache paths include both values. Signed-out and guest modes expose no authenticated media scope and therefore no authenticated pending tasks.

Switching server or account changes the active scope without deleting other scopes. Returning to the same server/account restores its pending uploads and cached covers. Clearing an authenticated cache explicitly removes the active scope's cover files; signing out alone retains them for offline reuse after a later sign-in to the same profile.

## Filesystem cover cache

### Storage layout

Cover bytes are stored as opaque files; image decoding uses the bytes rather than a filename extension.

- Native: the application-support directory contains `media-covers/<profile-key>/<user-id>/<media-id>.bin`.
- Web: OPFS contains the equivalent directory hierarchy.

Every write uses a temporary file or temporary OPFS entry followed by replacement so an interrupted write cannot leave a valid-looking partial cache entry. Cache path components are normalized before use, and callers cannot supply arbitrary paths.

### Cache behavior

A reusable cover loader follows this order:

1. If the book has a non-empty public/data `coverUrl`, render it through the existing network/data-image path.
2. If the book has `coverMediaId`, read the scoped cover file.
3. If a cached file exists, render it immediately.
4. Otherwise download the authenticated media asset, persist it in the active scope, and render it.
5. If local read or download fails, render the existing placeholder without deleting book metadata.

Downloads are coalesced by `(scope, mediaId)` so multiple widgets requesting the same cover share one operation. Completed futures are removed from the in-flight map; the persisted file, rather than a process-global future, is the long-lived cache.

### UI integration

A single reusable private-cover content widget owns the public-URL/private-media/placeholder decision. The existing sized `BookCoverImage` composes it, and library cards, list rows, dashboard cards, shelf/topic sheets, context menus, and other book-cover surfaces use the same content widget. This prevents successful upload from clearing `coverUrl` and making covers disappear outside the details page.

Book deletion removes the cached cover for that book on a best-effort basis after pending upload tasks are removed. Clearing the active authenticated cache removes the whole scoped cover directory. Guest book-file and cover storage remains untouched.

## Scoped upload queue

`MediaUploadQueue` manages tasks per media scope instead of using one global `media_upload_queue` preference key. Each persisted key includes a normalized server profile and user ID. Task payloads do not need to duplicate the scope because they are stored under the scoped key.

Changing the active scope reloads that scope's tasks and usage state, then notifies the UI. Guest or signed-out state activates no scope and presents an empty authenticated queue. Cover payloads remain in the scoped queue until upload succeeds; they never appear in another account's pending or failed list.

Queue processing is single-flight. If processing is already active, additional calls return the same future instead of iterating the task list again. The operation captures its media scope, `AuthRepository`, and local file reader at start, so a later profile switch cannot redirect in-flight work to another server. Results are saved back to the captured scope.

Enqueue and retry operations invoke a work-available callback only after the updated task list has been persisted. The application wires this callback to the existing media processor. This makes a newly imported book trigger its upload after enqueue, independently of PowerSync callback timing. PowerSync and authentication callbacks remain useful retry triggers and are safe because processing is single-flight.

## Server concurrency and quota integrity

The server serializes media uploads per user inside the database transaction:

1. Lock the authenticated user's row with `SELECT ... FOR UPDATE`.
2. Lock and validate the target book row.
3. Recalculate the user's used bytes while holding the user lock.
4. Stream the upload into a temporary file while enforcing the remaining quota.
5. Replace the prior `(book_id, kind)` asset and update the book reference.
6. Commit before deleting the previous physical file.

All uploads for one user therefore observe committed quota usage in order, including uploads for different books. Users do not block one another.

The `media_assets` table also has a unique constraint on `(book_id, kind)` as a defensive invariant. The SQLAlchemy model and the existing unmerged Alembic revision are amended together. Because the revision has not shipped or merged, updating it avoids creating a corrective migration for a schema no deployment should have consumed.

Rollback continues to remove temporary/new files and retain the previously committed asset. Physical-file deletion remains post-commit and best-effort.

## CI label correction

The mobile context-menu test asserts the product labels `Download` and `Delete`. No `book` suffix is added to the UI.

## Error handling

- Cover-cache failures degrade to a placeholder and remain retryable on a future build.
- A failed cache write does not hide successfully downloaded bytes during the current render, but it does not count as persisted.
- Queue network failures retain the task under its original scope.
- Storage-quota failures remain visible as failed tasks and require explicit retry.
- Profile switches never mutate or discard another scope's queue.
- Server constraint or transaction failures roll back database changes and remove the new temporary/final file.

## Testing strategy

All behavior changes follow red-green-refactor cycles.

Client tests cover:

- native/local cover-cache persistence, cache hits, atomic replacement, deletion, and scope isolation;
- web cover-store message handling and OPFS worker actions;
- lazy download followed by a persisted cache hit;
- shared in-flight cover downloads;
- private-cover rendering in details and representative library/dashboard surfaces;
- upload task isolation across server/user scopes;
- restoration of tasks when returning to a scope;
- single-flight processing under overlapping triggers;
- enqueue-triggered processing after persistence;
- profile switching while processing without backend redirection;
- corrected `Download` and `Delete` context-menu expectations.

Server tests cover:

- the `(book_id, kind)` uniqueness metadata and migration definition;
- concurrent same-kind uploads producing one stored asset;
- concurrent uploads for different books respecting aggregate user quota;
- replacement rollback retaining the old physical file;
- the existing upload, download, delete, ownership, and sync-reference behavior.

Final verification runs Flutter analysis and the full Flutter test suite, then Ruff, the full server pytest suite, Alembic single-head inspection, and migration upgrade/downgrade/upgrade against the test database when the repository runbook environment is available.
