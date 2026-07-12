# Media Storage Hardening Design

## Context

The media-storage pipeline spans the Papyrus Flutter client and FastAPI server. Book metadata is synchronized through PowerSync while book files and cover images remain private media assets stored outside the synchronized database.

Guest and account libraries are intentionally separate. Signing in does not migrate or merge guest books, files, covers, or pending work into an account library. Guest covers remain permanent local media, while account covers use a local-first upload and cross-device cache lifecycle.

## Goals

- Persist authenticated cover images in platform-local files after their first successful display.
- Persist newly imported guest and account covers in platform-local files before book metadata is saved.
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

Together they form an immutable media scope for one server/account pair. Upload tasks, pending-cover paths, and cover-cache paths include both values. Signed-out and guest modes expose no authenticated upload scope and therefore no authenticated pending tasks. The single guest library uses a distinct local-only namespace for its permanent cover files.

Switching server or account changes the active scope without deleting other scopes. Returning to the same server/account restores its pending uploads and cached covers. Clearing an authenticated cache explicitly removes the active scope's cover files; signing out alone retains them for offline reuse after a later sign-in to the same profile.

## Filesystem cover cache

### Storage layout

Cover bytes are stored as opaque files; image decoding uses the bytes rather than a filename extension.

- Native: the application-support directory contains `media-covers/<profile-key>/<user-id>/cached/<media-id>.bin` and `media-covers/<profile-key>/<user-id>/pending/<book-id>.bin`.
- Web: OPFS contains the equivalent directory hierarchy.
- Guest covers use the equivalent `media-covers/local/guest/books/<book-id>.bin` layout and never enter an authenticated scope.

Every write uses a temporary file or temporary OPFS entry followed by replacement so an interrupted write cannot leave a valid-looking partial cache entry. Cache path components are normalized before use, and callers cannot supply arbitrary paths.

### Cache behavior

A reusable cover loader follows this order:

1. If the book has a non-empty public HTTP(S) `coverUrl`, render it through the existing network-image path. Legacy `data:` values remain readable for backward compatibility, but new imports and edits never create them.
2. If the book has `coverMediaId`, read the authenticated scoped cache file.
3. If the cached media file exists, render it immediately.
4. Otherwise download the authenticated media asset, persist it in the active scope, and render it.
5. If the book has no `coverMediaId`, look for a pending account cover or permanent guest cover derived from the book ID and active library mode.
6. If local read or download fails, render the existing placeholder without deleting book metadata.

Downloads are coalesced by `(scope, mediaId)` so multiple widgets requesting the same cover share one operation. Completed futures are removed from the in-flight map; the persisted file, rather than a process-global future, is the long-lived cache.

### UI integration

A single reusable private-cover content widget owns the public-URL/private-media/placeholder decision. The existing sized `CoverImagePreview` composes it, and library cards, list rows, dashboard cards, shelf/topic sheets, context menus, and other book-cover surfaces use the same content widget. This prevents successful upload from clearing `coverUrl` and making covers disappear outside the details page.

Book deletion removes pending, guest, and cached cover files for that book on a best-effort basis after pending upload tasks are removed. Clearing the active authenticated cache removes the whole scoped cover directory. Clearing authenticated data never removes guest book-file or cover storage.

## Two-mode cover lifecycle

### Fully offline guest library

Import writes the extracted cover to the guest filesystem/OPFS namespace before saving book metadata. The book row contains no cover bytes or device-local path. Cover widgets derive the local cover key from the book ID and guest library mode. The cover remains local permanently unless the guest book is deleted. Signing in does not migrate it.

### Account library and cross-device synchronization

Account imports are local-first and remain usable without network connectivity:

1. Write the extracted cover to the active server/user scope under `pending/<book-id>.bin`.
2. Save and synchronize book metadata without cover bytes, a data URI, or a device-local path.
3. Persist a media upload task that references the pending cover key rather than embedding cover bytes.
4. After PowerSync has created the owned server book, upload the pending cover.
5. The server stores the private asset, updates `cover_media_id`, and exposes that portable ID through PowerSync.
6. Promote the source device's pending bytes into the scoped `<media-id>.bin` cache and remove the pending file.
7. Other devices receive `cover_media_id`, lazily download the authenticated asset when first displayed, and persist their own scoped cache file.

An account device that remains offline keeps its pending file and durable queue task until connectivity returns. Another device may show a placeholder before `cover_media_id` is available; it never receives a local path or raw cover bytes through synchronization. Concurrent replacements retain the server's existing last-committed replacement behavior.

## Scoped upload queue

`MediaUploadQueue` manages tasks per media scope instead of using one global `media_upload_queue` preference key. Each persisted key includes a normalized server profile and user ID. Task payloads do not duplicate the scope because they are stored under the scoped key. Cover tasks store only the book ID, pending-cover key, filename, content type, status, and error state; cover bytes remain in filesystem/OPFS and never enter SharedPreferences.

Changing the active scope reloads that scope's tasks and usage state, then notifies the UI. Guest or signed-out state activates no scope and presents an empty authenticated queue. Cover task references remain in the scoped queue until upload succeeds; they never appear in another account's pending or failed list.

Queue processing is single-flight. If processing is already active, additional calls return the same future and request one additional drain pass so a PowerSync completion signal cannot be lost behind an earlier `Book was not found` response. The operation captures its media scope, `AuthRepository`, and local file readers at start, so a later profile switch cannot redirect in-flight work to another server. Results are saved back to the captured scope.

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
- A missing server book leaves account media pending until a later PowerSync completion trigger retries it.
- A failed pending-cover read retains both the file reference and queue task.
- Storage-quota failures remain visible as failed tasks and require explicit retry.
- Profile switches never mutate or discard another scope's queue.
- Server constraint or transaction failures roll back database changes and remove the new temporary/final file.

## Testing strategy

All behavior changes follow red-green-refactor cycles.

Client tests cover:

- native/local cover-cache persistence, cache hits, atomic replacement, deletion, and scope isolation;
- web cover-store message handling and OPFS worker actions;
- guest cover persistence derived from book ID without SQL metadata bytes;
- account pending-cover persistence and restoration without SharedPreferences payload bytes;
- pending-cover promotion to `coverMediaId` cache after upload;
- cross-device behavior where a device with only `coverMediaId` lazily downloads its own cache;
- lazy download followed by a persisted cache hit;
- shared in-flight cover downloads;
- private-cover rendering in details and representative library/dashboard surfaces;
- upload task isolation across server/user scopes;
- restoration of tasks when returning to a scope;
- single-flight processing under overlapping triggers;
- a PowerSync retry trigger arriving during a failed media request causing an additional drain pass;
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
