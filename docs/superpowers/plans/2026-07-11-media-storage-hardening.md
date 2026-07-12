# Media Storage Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make authenticated covers persist in scoped local files, serialize and scope client uploads, close the enqueue race, harden server upload concurrency, and restore client CI while preserving separate guest libraries.

**Architecture:** Introduce a shared `MediaStorageScope` for server/account isolation, extend the existing native-filesystem/web-OPFS book storage service with scoped cover-file operations, and route every private cover through one lazy persistent loader. Make `MediaUploadQueue` scope-aware and single-flight, then serialize server uploads with a PostgreSQL user-row lock plus a unique `(book_id, kind)` invariant.

**Tech Stack:** Flutter/Dart, SharedPreferences, native filesystem, web OPFS/Web Worker, PowerSync, FastAPI, async SQLAlchemy, PostgreSQL, Alembic, pytest.

---

## File structure

Client files to create:

- `app/lib/media/media_storage_scope.dart`: immutable server/user scope and safe persistence key.
- `app/lib/widgets/book/private_book_cover.dart`: reusable public/private/local cover renderer.
- `app/test/media/media_storage_scope_test.dart`: scope identity and normalization tests.
- `app/test/widgets/book/private_book_cover_test.dart`: lazy cache and placeholder widget tests.

Client files to modify:

- `app/lib/services/book_import_service_stub.dart`: native scoped cover-file storage.
- `app/lib/services/book_import_service.dart`: web worker cover-file request methods.
- `app/web/book_worker.js`: scoped OPFS cover read/write/delete/clear actions.
- `app/lib/media/media_cache_service.dart`: lazy cover cache and in-flight coalescing.
- `app/lib/media/media_upload_queue.dart`: scoped keys, scope activation, single-flight processing, and persisted-work callback.
- `app/lib/main.dart`: scope lifecycle, stable repository capture, and queue callback wiring.
- `app/lib/services/book_delete_cleanup_service.dart`: best-effort cached-cover deletion.
- `app/lib/widgets/book_details/book_cover_image.dart`: compose the shared cover renderer.
- Cover surfaces under `app/lib/widgets/library/`, `app/lib/widgets/dashboard/`, `app/lib/widgets/context_menu/`, `app/lib/widgets/shelves/`, and `app/lib/widgets/topics/`: pass `coverMediaId` to the shared renderer.
- Existing media, deletion, widget, profile-switch, and context-menu tests.

Server files to modify:

- `papyrus/models/media.py`: unique `(book_id, kind)` model invariant.
- `alembic/versions/c3f8b2a9d1e4_add_media_assets.py`: matching unique constraint in the unmerged revision.
- `papyrus/services/media.py`: per-user transaction lock and locked book lookup.
- `tests/api/routes/test_media.py`: concurrent replacement and quota tests.
- `tests/test_models.py`: metadata constraint assertion.

### Task 1: Restore the intended context-menu contract

**Files:**

- Modify: `app/test/widgets/context_menu/book_context_menu_test.dart:11-45`
- Verify: `app/lib/widgets/context_menu/book_context_menu.dart:421-442`

- [ ] **Step 1: Change the failing test to assert the approved labels**

```dart
final downloadTop = tester.getTopLeft(find.text('Download')).dy;
final deleteTop = tester.getTopLeft(find.text('Delete')).dy;
expect(downloadTop, lessThan(deleteTop));

await tester.tap(find.text('Download'));
```

- [ ] **Step 2: Run the focused test and verify it passes without production changes**

Run: `cd app && flutter test test/widgets/context_menu/book_context_menu_test.dart`

Expected: one passing test. This is an assertion correction for an already-approved UI contract, so no red production cycle is required.

- [ ] **Step 3: Commit the CI correction**

```bash
git add app/test/widgets/context_menu/book_context_menu_test.dart
git commit -m "test: align book menu labels"
```

### Task 2: Define authenticated media scope

**Files:**

- Create: `app/lib/media/media_storage_scope.dart`
- Create: `app/test/media/media_storage_scope_test.dart`

- [ ] **Step 1: Write failing scope tests**

```dart
test('scope key isolates server and user', () {
  final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  final second = MediaStorageScope(profileKey: 'custom-deadbeef', userId: 'user-1');

  expect(first.persistenceKey, isNot(second.persistenceKey));
  expect(first.persistenceKey, 'official--user-1');
});

test('scope rejects path separators', () {
  expect(
    () => MediaStorageScope(profileKey: '../official', userId: 'user-1'),
    throwsArgumentError,
  );
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `cd app && flutter test test/media/media_storage_scope_test.dart`

Expected: compilation failure because `MediaStorageScope` does not exist.

- [ ] **Step 3: Add the immutable scope type**

```dart
class MediaStorageScope {
  MediaStorageScope({required this.profileKey, required this.userId}) {
    if (!_safePart.hasMatch(profileKey) || !_safePart.hasMatch(userId)) {
      throw ArgumentError('Media storage scope contains unsafe characters');
    }
  }

  static final RegExp _safePart = RegExp(r'^[a-zA-Z0-9_.-]+$');

  final String profileKey;
  final String userId;

  String get persistenceKey => '$profileKey--$userId';

  @override
  bool operator ==(Object other) =>
      other is MediaStorageScope && other.profileKey == profileKey && other.userId == userId;

  @override
  int get hashCode => Object.hash(profileKey, userId);
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `cd app && flutter test test/media/media_storage_scope_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit the scope type**

```bash
git add app/lib/media/media_storage_scope.dart app/test/media/media_storage_scope_test.dart
git commit -m "feat: define scoped media identity"
```

### Task 3: Add filesystem and OPFS cover-file operations

**Files:**

- Modify: `app/lib/services/book_import_service_stub.dart`
- Modify: `app/lib/services/book_import_service.dart`
- Modify: `app/web/book_worker.js`
- Create: `app/test/services/book_cover_storage_test.dart`
- Modify: `app/test/services/book_import_service_test.dart`

- [ ] **Step 1: Write failing native cover-storage tests with an injected root directory**

```dart
test('native cover storage is isolated by scope', () async {
  final root = await Directory.systemTemp.createTemp('papyrus-covers-');
  addTearDown(() => root.delete(recursive: true));
  final service = BookImportService(storageRootOverride: root);
  final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  final second = MediaStorageScope(profileKey: 'official', userId: 'user-2');
  final bytes = Uint8List.fromList([1, 2, 3]);

  await service.storeCoverFile(first, 'asset-1', bytes);

  expect(await service.getCoverFile(first, 'asset-1'), bytes);
  expect(await service.getCoverFile(second, 'asset-1'), isNull);
});

test('clearCoverFiles removes only the selected scope', () async {
  final root = await Directory.systemTemp.createTemp('papyrus-covers-');
  addTearDown(() => root.delete(recursive: true));
  final service = BookImportService(storageRootOverride: root);
  final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  final second = MediaStorageScope(profileKey: 'official', userId: 'user-2');

  await service.storeCoverFile(first, 'asset-1', Uint8List.fromList([1]));
  await service.storeCoverFile(second, 'asset-2', Uint8List.fromList([2]));
  await service.clearCoverFiles(first);

  expect(await service.getCoverFile(first, 'asset-1'), isNull);
  expect(await service.getCoverFile(second, 'asset-2'), Uint8List.fromList([2]));
});
```

- [ ] **Step 2: Run the native tests and verify RED**

Run: `cd app && flutter test test/services/book_cover_storage_test.dart`

Expected: missing constructor parameter and cover methods.

- [ ] **Step 3: Implement native scoped file operations**

Add methods with these signatures:

```dart
Future<Uint8List?> getCoverFile(MediaStorageScope scope, String mediaId);
Future<void> storeCoverFile(MediaStorageScope scope, String mediaId, Uint8List bytes);
Future<void> deleteCoverFile(MediaStorageScope scope, String mediaId);
Future<void> clearCoverFiles(MediaStorageScope scope);
```

Use `<root>/media-covers/<scope.persistenceKey>/<mediaId>.bin`. Validate `mediaId` with the same safe-component rule. Write `<mediaId>.tmp`, flush it, then rename it over the destination. Add `Directory? storageRootOverride` for tests; production falls back to `getApplicationSupportDirectory()`.

- [ ] **Step 4: Run native tests and verify GREEN**

Run: `cd app && flutter test test/services/book_cover_storage_test.dart test/services/book_import_service_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Write a failing worker-contract test**

```dart
test('book worker declares scoped cover cache actions', () {
  final source = File('web/book_worker.js').readAsStringSync();
  for (final action in ['getCover', 'storeCover', 'deleteCover', 'clearCovers']) {
    expect(source, contains("case '$action':"));
  }
});
```

- [ ] **Step 6: Run the worker-contract test and verify RED**

Run: `cd app && flutter test test/services/book_cover_storage_test.dart`

Expected: missing `getCover` action.

- [ ] **Step 7: Extend the OPFS worker and web service**

Add `getCover`, `storeCover`, `deleteCover`, and `clearCovers` messages containing `scopeKey`, `mediaId`, and a stable `requestId`. Store files under the OPFS `media-covers/<scopeKey>/` directory. Update the Dart pending map to key cover requests by `requestId`, transfer downloaded/stored `ArrayBuffer` values, and expose the same four Dart method signatures as the native implementation.

- [ ] **Step 8: Verify worker syntax and focused Flutter tests**

Run: `node --check app/web/book_worker.js`

Run: `cd app && flutter test test/services/book_cover_storage_test.dart test/services/book_import_service_test.dart`

Expected: JavaScript syntax succeeds and all focused tests pass.

- [ ] **Step 9: Commit platform cover storage**

```bash
git add app/lib/services/book_import_service.dart app/lib/services/book_import_service_stub.dart app/web/book_worker.js app/test/services/book_cover_storage_test.dart app/test/services/book_import_service_test.dart
git commit -m "feat: persist scoped covers in local files"
```

### Task 4: Add lazy persistent cover loading and shared rendering

**Files:**

- Modify: `app/lib/media/media_cache_service.dart`
- Modify: `app/test/media/media_cache_service_test.dart`
- Create: `app/lib/widgets/book/private_book_cover.dart`
- Create: `app/test/widgets/book/private_book_cover_test.dart`
- Modify: `app/lib/widgets/book_details/book_cover_image.dart`
- Modify representative and remaining cover surfaces found by `rg -n "coverURL|coverUrl" app/lib/widgets app/lib/pages`

- [ ] **Step 1: Write failing lazy-cache and coalescing tests**

```dart
test('cover download persists and the next load reads local bytes', () async {
  final service = MediaCacheService();
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  Uint8List? stored;
  var downloads = 0;

  final first = await service.ensureCoverCached(
    scope: scope,
    mediaId: 'asset-1',
    readLocalCover: (_, __) async => stored,
    writeLocalCover: (_, __, bytes) async => stored = bytes,
    downloadMedia: (_) async {
      downloads++;
      return Uint8List.fromList([1, 2, 3]);
    },
  );
  final second = await service.ensureCoverCached(
    scope: scope,
    mediaId: 'asset-1',
    readLocalCover: (_, __) async => stored,
    writeLocalCover: (_, __, bytes) async => stored = bytes,
    downloadMedia: (_) async {
      downloads++;
      return Uint8List.fromList([1, 2, 3]);
    },
  );

  expect(first, second);
  expect(downloads, 1);
});

test('overlapping cover requests share one download', () async {
  final service = MediaCacheService();
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  final gate = Completer<Uint8List>();
  var downloads = 0;

  Future<Uint8List> load() => service.ensureCoverCached(
    scope: scope,
    mediaId: 'asset-1',
    readLocalCover: (_, __) async => null,
    writeLocalCover: (_, __, ___) async {},
    downloadMedia: (_) {
      downloads++;
      return gate.future;
    },
  );

  final first = load();
  final second = load();
  gate.complete(Uint8List.fromList([1, 2, 3]));

  expect(await first, await second);
  expect(downloads, 1);
});
```

- [ ] **Step 2: Run cache tests and verify RED**

Run: `cd app && flutter test test/media/media_cache_service_test.dart`

Expected: `ensureCoverCached` is missing.

- [ ] **Step 3: Implement cover caching in `MediaCacheService`**

Use a `Map<String, Future<Uint8List>>` keyed by `<scope.persistenceKey>:<mediaId>`. Read local bytes first; otherwise coalesce download/write work. Remove the map entry in `whenComplete` so the filesystem remains the durable cache.

- [ ] **Step 4: Run cache tests and verify GREEN**

Run: `cd app && flutter test test/media/media_cache_service_test.dart`

Expected: all book-file and cover-cache tests pass.

- [ ] **Step 5: Write failing widget tests for a private cover**

```dart
testWidgets('private cover loads from scoped local cache', (tester) async {
  final bytes = Uint8List.fromList([137, 80, 78, 71]);
  var loads = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: CoverImage(
        mediaId: 'asset-1',
        loadPrivateCover: (_) async {
          loads++;
          return bytes;
        },
        placeholder: const Icon(Icons.menu_book),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(Image), findsOneWidget);
  expect(loads, 1);
});

testWidgets('private cover falls back to placeholder when signed out', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: CoverImage(
        mediaId: 'asset-1',
        placeholder: Icon(Icons.menu_book, key: Key('placeholder')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('placeholder')), findsOneWidget);
});
```

- [ ] **Step 6: Run widget tests and verify RED**

Run: `cd app && flutter test test/widgets/book/private_book_cover_test.dart`

Expected: `CoverImage` does not exist.

- [ ] **Step 7: Implement `CoverImage` and integrate `CoverImagePreview`**

The stateful widget accepts `imageUrl`, `mediaId`, `fit`, and a placeholder builder. It caches its future until `mediaId` or scope changes, uses the active `MediaStorageScope`, reads/writes through `BookImportService`, downloads through `AuthProvider`, and delegates lazy caching to `MediaCacheService`.

- [ ] **Step 8: Replace private-cover-blind surfaces**

Use `CoverImage` in library cards/list rows, recently-added and continue-reading dashboard cards, move-to-shelf and manage-topics sheets, and `BookContextMenu`. Pass both `book.coverURL` and `book.coverMediaId`; preserve each surface's existing dimensions, fit, and placeholder styling.

- [ ] **Step 9: Run focused cover widget tests and analyzer**

Run: `cd app && flutter test test/widgets/book/private_book_cover_test.dart test/widgets/library/book_card_test.dart test/widgets/library/book_list_item_test.dart`

Run: `cd app && flutter analyze`

Expected: focused tests and analysis pass.

- [ ] **Step 10: Commit lazy cover rendering**

```bash
git add app/lib/media/media_cache_service.dart app/lib/widgets app/test/media/media_cache_service_test.dart app/test/widgets
git commit -m "feat: render private covers from persistent cache"
```

### Task 5: Scope upload tasks and make processing single-flight

**Files:**

- Modify: `app/lib/media/media_upload_queue.dart`
- Modify: `app/test/media/media_upload_queue_test.dart`

- [ ] **Step 1: Write failing scope-isolation tests**

```dart
test('pending uploads are isolated and restored per media scope', () async {
  final queue = MediaUploadQueue(prefs);
  final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  final second = MediaStorageScope(profileKey: 'custom-a', userId: 'user-2');

  await queue.activateScope(first);
  await queue.enqueueBookFile(book: book, filename: 'book.epub', contentType: 'application/epub+zip');
  await queue.activateScope(second);
  expect(queue.pendingTasks, isEmpty);
  await queue.activateScope(first);
  expect(queue.pendingTasks, hasLength(1));
});
```

- [ ] **Step 2: Run the isolation test and verify RED**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart --plain-name "pending uploads are isolated"`

Expected: `activateScope` is missing.

- [ ] **Step 3: Implement scoped persistence**

Replace the global key with `media_upload_queue:<scope.persistenceKey>`. `activateScope(null)` exposes an empty queue. Loading malformed JSON should preserve app startup by returning an empty task list and reporting through `FlutterError.reportError`.

- [ ] **Step 4: Run queue tests and verify scope GREEN**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart`

Expected: scope tests pass; update existing assertions to inspect the scoped key.

- [ ] **Step 5: Write a failing overlapping-processing test**

```dart
test('overlapping processPending calls share one upload operation', () async {
  final gate = Completer<MediaAsset>();
  var uploads = 0;
  Future<void> process() => queue.processPending(
    dataStore: dataStore,
    readBookFile: (_) async => Uint8List.fromList([1, 2, 3]),
    uploadMedia: (_) {
      uploads++;
      return gate.future;
    },
  );

  final first = process();
  final second = process();
  expect(identical(first, second), isTrue);
  gate.complete(asset);
  await Future.wait([first, second]);
  expect(uploads, 1);
});
```

- [ ] **Step 6: Run the overlap test and verify RED**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart --plain-name "overlapping processPending"`

Expected: two uploads or non-identical futures.

- [ ] **Step 7: Implement single-flight processing**

Track `Future<void>? _processing`. Return the current future when non-null, capture the active scope at operation start, and clear the field only when the identical operation completes. Expose `Future<void> waitUntilIdle()` for profile changes.

- [ ] **Step 8: Run all queue tests and verify GREEN**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart`

Expected: all tests pass.

- [ ] **Step 9: Commit queue isolation and serialization**

```bash
git add app/lib/media/media_upload_queue.dart app/test/media/media_upload_queue_test.dart
git commit -m "fix: scope and serialize media uploads"
```

### Task 6: Trigger uploads after durable enqueue and coordinate profile changes

**Files:**

- Modify: `app/lib/media/media_upload_queue.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart`
- Modify: `app/test/media/media_upload_queue_test.dart`
- Modify: `app/test/powersync/storage_sync_controller_test.dart`
- Modify or create: `app/test/main_media_lifecycle_test.dart`

- [ ] **Step 1: Write a failing persisted-work callback test**

```dart
test('enqueue invokes work callback after scoped tasks are persisted', () async {
  String? storedAtCallback;
  late SharedPreferences prefs;
  final queue = MediaUploadQueue(
    prefs,
    onWorkAvailable: () async {
      storedAtCallback = prefs.getString('media_upload_queue:${scope.persistenceKey}');
    },
  );

  await queue.activateScope(scope);
  await queue.enqueueBookFile(
    book: book,
    filename: 'book.epub',
    contentType: 'application/epub+zip',
  );
  expect(storedAtCallback, isNotNull);
  expect(jsonDecode(storedAtCallback!), hasLength(1));
});
```

- [ ] **Step 2: Run the callback test and verify RED**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart --plain-name "enqueue invokes work callback"`

Expected: constructor does not accept `onWorkAvailable`.

- [ ] **Step 3: Implement the post-persistence callback**

Add `Future<void> Function()? onWorkAvailable`. Invoke it after `_save()` in `_enqueue` and after `retryFailed` makes at least one task pending. Do not invoke it from internal task-status saves.

- [ ] **Step 4: Run queue tests and verify GREEN**

Run: `cd app && flutter test test/media/media_upload_queue_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Write failing lifecycle tests**

Cover three concrete cases in `main_media_lifecycle_test.dart`: a signed-in import persists a task before its fake uploader is invoked; a server switch remains incomplete while a fake upload `Completer` is pending and activates the new scope after completion; and guest activation leaves `MediaUploadQueue.activeScope` null with no visible authenticated tasks. Build the harness with injected fake `AuthRepository`, `PapyrusPowerSyncService`, and uploader closures, then assert invocation order through a shared event list.

- [ ] **Step 6: Run lifecycle tests and verify RED**

Run: `cd app && flutter test test/main_media_lifecycle_test.dart`

Expected: missing scope activation/callback wiring.

- [ ] **Step 7: Wire scope and processing lifecycle in `main.dart`**

Construct `MediaStorageScope(profileKey: _activeProfileKey, userId: user.userId)` only for signed-in account mode. Activate it before processing. Capture `final repository = _authRepository` inside each processor operation. Before replacing the repository during a server switch, await `_mediaUploadQueue.waitUntilIdle()`. Wire `onWorkAvailable` to `_processMediaUploads`; single-flight makes authentication and PowerSync triggers safe.

Remove any direct process call from the import widget if the queue callback makes it redundant. Keep the import sequence awaiting both book-file and cover enqueue operations so the callback sees durable work.

- [ ] **Step 8: Run lifecycle and import tests**

Run: `cd app && flutter test test/main_media_lifecycle_test.dart test/services/book_import_service_test.dart test/media/media_upload_queue_test.dart`

Expected: all tests pass.

- [ ] **Step 9: Commit enqueue/lifecycle coordination**

```bash
git add app/lib/main.dart app/lib/media/media_upload_queue.dart app/lib/widgets/add_book/import_book_sheet.dart app/test
git commit -m "fix: process media immediately after enqueue"
```

### Task 7: Clean cached covers with book/account cache deletion

**Files:**

- Modify: `app/lib/services/book_delete_cleanup_service.dart`
- Modify callers in `app/lib/pages/book_details_page.dart`, `app/lib/utils/book_actions.dart`, and `app/lib/utils/bulk_book_actions.dart`
- Modify: `app/test/services/book_delete_cleanup_service_test.dart`
- Modify authenticated-cache clearing path in `app/lib/main.dart` or `app/lib/powersync/storage_sync_controller.dart`

- [ ] **Step 1: Write a failing deletion test**

```dart
test('deleteBookWithMediaCleanup removes the scoped cached cover', () async {
  final deletedCovers = <String>[];
  await deleteBookWithMediaCleanup(
    dataStore: dataStore,
    mediaUploadQueue: queue,
    bookId: book.id,
    coverMediaId: 'cover-1',
    deleteBookFile: (_) async {},
    deleteCoverFile: (mediaId) async => deletedCovers.add(mediaId),
  );
  expect(deletedCovers, ['cover-1']);
});
```

- [ ] **Step 2: Run the deletion test and verify RED**

Run: `cd app && flutter test test/services/book_delete_cleanup_service_test.dart`

Expected: missing cover parameters.

- [ ] **Step 3: Implement best-effort cover cleanup and update callers**

Remove scoped upload tasks first, then independently attempt local book-file and cover-file deletion, finally delete metadata. Pass the current book's `coverMediaId` and a closure bound to the active `MediaStorageScope`.

- [ ] **Step 4: Add and pass an authenticated-cache-clear test**

Assert clearing the active authenticated cache invokes `clearCoverFiles(activeScope)` but guest clearing does not.

- [ ] **Step 5: Run deletion/profile tests and commit**

Run: `cd app && flutter test test/services/book_delete_cleanup_service_test.dart test/pages/book_details_delete_test.dart test/powersync/storage_sync_controller_test.dart`

Expected: all tests pass.

```bash
git add app/lib app/test
git commit -m "fix: clean scoped cover files"
```

### Task 8: Enforce one server asset per book kind and serialize quota checks

**Files:**

- Modify: `../server/papyrus/models/media.py`
- Modify: `../server/alembic/versions/c3f8b2a9d1e4_add_media_assets.py`
- Modify: `../server/papyrus/services/media.py`
- Modify: `../server/tests/test_models.py`
- Modify: `../server/tests/api/routes/test_media.py`

- [ ] **Step 1: Write a failing metadata constraint test**

```python
def test_media_asset_kind_is_unique_per_book() -> None:
    table = Base.metadata.tables['media_assets']
    unique_columns = {
        tuple(constraint.columns.keys())
        for constraint in table.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert ('book_id', 'kind') in unique_columns
```

- [ ] **Step 2: Run the model test and verify RED**

Run: `cd ../server && .venv/bin/pytest tests/test_models.py -q`

Expected: the unique column pair is absent.

- [ ] **Step 3: Add the SQLAlchemy and Alembic constraint**

```python
__table_args__ = (
    UniqueConstraint('book_id', 'kind', name='uq_media_assets_book_kind'),
)
```

Add the equivalent `sa.UniqueConstraint` to `c3f8b2a9d1e4_add_media_assets.py`. Do not create a new revision because this revision is unmerged and undeployed.

- [ ] **Step 4: Run the model test and verify GREEN**

Run: `cd ../server && .venv/bin/pytest tests/test_models.py -q`

Expected: all model tests pass.

- [ ] **Step 5: Write failing concurrent upload tests**

Using `test_session_maker`, create two independent `AsyncSession` instances and start two `media_service.upload_media` coroutines with `asyncio.gather`. In `test_concurrent_same_kind_uploads_leave_one_asset`, target one user/book/kind and assert exactly one `MediaAsset` row, the book references that row, and exactly one physical file remains. In `test_concurrent_uploads_enforce_aggregate_user_quota`, target two books owned by one user with two files whose combined size exceeds the configured quota; assert one coroutine succeeds, one returns `ConflictError`, and both the SQL sum and physical-file sum remain at or below quota.

- [ ] **Step 6: Run concurrent tests and verify RED**

Run: `cd ../server && .venv/bin/pytest tests/api/routes/test_media.py -q -k concurrent`

Expected: duplicate assets or quota overflow.

- [ ] **Step 7: Lock the user and book rows before quota/replacement reads**

Add transaction helpers equivalent to:

```python
await session.execute(
    select(User.user_id).where(User.user_id == user_id).with_for_update()
)
book = (
    await session.execute(
        select(SyncBook)
        .where(SyncBook.book_id == book_id)
        .with_for_update()
    )
).scalar_one_or_none()
```

Acquire the user lock first for every upload, then validate the locked book, calculate usage, stream/write, replace, and commit. Keep the existing rollback cleanup and post-commit old-file deletion.

- [ ] **Step 8: Run media and sync tests and verify GREEN**

Run: `cd ../server && .venv/bin/pytest tests/api/routes/test_media.py tests/api/routes/test_sync.py -q`

Expected: all focused server tests pass.

- [ ] **Step 9: Verify migration shape**

Run: `cd ../server && .venv/bin/alembic heads`

Expected: one head, `c3f8b2a9d1e4`.

Run, when the runbook database is available:

```bash
cd ../server
.venv/bin/alembic downgrade a1d7c2f4e8b9
.venv/bin/alembic upgrade head
.venv/bin/alembic downgrade a1d7c2f4e8b9
.venv/bin/alembic upgrade head
```

Expected: every command succeeds and the final revision is `c3f8b2a9d1e4`.

- [ ] **Step 10: Commit server hardening**

```bash
cd ../server
git add papyrus/models/media.py papyrus/services/media.py alembic/versions/c3f8b2a9d1e4_add_media_assets.py tests/test_models.py tests/api/routes/test_media.py
git commit -m "fix: serialize media storage updates"
```

### Task 9: Full verification and PR readiness

**Files:**

- Review all files changed by Tasks 1-8.

- [ ] **Step 1: Run client formatting and diff checks**

Run: `cd app && dart format --output=none --set-exit-if-changed lib test`

Run: `git diff --check origin/master...HEAD`

Expected: both pass.

- [ ] **Step 2: Run full client verification**

Run: `cd app && flutter analyze`

Run: `cd app && flutter test`

Run: `node --check app/web/book_worker.js`

Expected: no analyzer issues and all tests pass.

- [ ] **Step 3: Run server formatting/lint and full tests**

Run: `cd ../server && .venv/bin/ruff format --check papyrus tests alembic`

Run: `cd ../server && .venv/bin/ruff check papyrus tests alembic`

Run: `cd ../server && .venv/bin/pytest -q`

Expected: formatting and lint pass; all non-provider tests pass with only the established opt-in skips.

- [ ] **Step 4: Confirm clean scoped behavior manually from code paths**

Check that:

- guest activation uses no `MediaStorageScope`;
- sign-out does not delete another account's queue/cache;
- server switch waits for queue idle and captures the old repository;
- every book-cover surface found by `rg -n "coverURL|coverUrl" app/lib/widgets app/lib/pages` either uses `CoverImage` or intentionally renders a public-only decorative URL;
- no cover bytes are stored in SQL or SharedPreferences.

- [ ] **Step 5: Inspect GitHub checks without changing remote state**

Run:

```bash
gh pr checks 16 --repo PapyrusReader/client
gh pr checks 3 --repo PapyrusReader/server
```

Expected: existing remote checks may still reflect prior commits until pushed; report this distinction explicitly.

- [ ] **Step 6: Report final commits, test counts, migration caveats, and any residual risk**

Do not claim either PR passes until the fresh commands above prove it locally. Do not push or submit GitHub reviews unless separately requested.
