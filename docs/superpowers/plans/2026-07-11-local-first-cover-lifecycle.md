# Local-First Cover Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep guest and account cover bytes in filesystem/OPFS, synchronize only `cover_media_id`, and make account covers survive offline import and appear on other devices through lazy authenticated downloads.

**Architecture:** Extend the existing scoped cover store with explicit cached, pending, and guest-book buckets. Account imports write `pending/<book-id>.bin`, synchronize metadata without an inline cover, and enqueue a metadata-only cover task; successful upload promotes those bytes to `cached/<media-id>.bin`. Guest imports write `local/guest/books/<book-id>.bin`, while other account devices receive `cover_media_id` and reuse the existing lazy cache downloader.

**Tech Stack:** Flutter/Dart, `SharedPreferences`, native filesystem through `path_provider`, web OPFS through `book_worker.js`, PowerSync, Flutter widget/unit tests.

---

## File structure

- Create `app/lib/media/cover_storage_bucket.dart`: safe bucket names shared by native and web cover storage.
- Create `app/lib/services/book_import_commit_service.dart`: one testable import-commit boundary that persists a cover before saving metadata and enqueueing account media.
- Create `app/test/services/book_import_commit_service_test.dart`: verifies guest/account behavior without widget timing.
- Modify `app/lib/media/media_storage_scope.dart`: add the single local guest cover namespace.
- Modify `app/lib/services/book_import_service_stub.dart`: native cached, pending, and guest cover operations.
- Modify `app/lib/services/book_import_service.dart`: matching web worker requests and pending-to-cache promotion.
- Modify `app/web/book_worker.js`: validate a cover bucket and store files beneath that bucket.
- Modify `app/lib/media/media_upload_queue.dart`: persist cover task metadata only and read pending bytes at processing time.
- Modify `app/lib/widgets/add_book/import_book_sheet.dart`: delegate committing to the new service; stop generating new data URIs.
- Modify `app/lib/widgets/book/private_book_cover.dart`: load a book-ID fallback when no public URL or media ID exists.
- Modify cover call sites and `CoverPreview`: propagate book IDs to the shared cover renderer.
- Modify `app/lib/main.dart`: promote uploaded pending cover bytes to the media-ID cache.
- Modify book deletion cleanup: delete pending/guest files as well as media-ID cache files.

### Task 1: Add explicit filesystem cover buckets

**Files:**

- Create: `app/lib/media/cover_storage_bucket.dart`
- Modify: `app/lib/media/media_storage_scope.dart`
- Modify: `app/lib/services/book_import_service_stub.dart`
- Modify: `app/lib/services/book_import_service.dart`
- Modify: `app/web/book_worker.js`
- Test: `app/test/services/book_cover_storage_test.dart`
- Test: `app/test/media/media_storage_scope_test.dart`

- [ ] **Step 1: Write failing native storage and guest-scope tests**

Add tests that exercise the wished-for API:

```dart
test('pending and cached covers use separate files', () async {
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  await service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([1]));
  await service.storeCoverFile(scope, 'asset-1', Uint8List.fromList([2]));

  expect(await service.getPendingCoverFile(scope, 'book-1'), [1]);
  expect(await service.getCoverFile(scope, 'asset-1'), [2]);
});

test('guest cover files use the local guest namespace', () async {
  await service.storeGuestCoverFile('book-1', Uint8List.fromList([3]));
  expect(await service.getGuestCoverFile('book-1'), [3]);
  expect(MediaStorageScope.localGuest.persistenceKey, 'local--guest');
});

test('promotion stores media cache bytes and removes pending file', () async {
  final scope = MediaStorageScope(profileKey: 'official', userId: 'user-1');
  await service.storePendingCoverFile(scope, 'book-1', Uint8List.fromList([4]));
  await service.promotePendingCoverFile(scope, bookId: 'book-1', mediaId: 'asset-1');

  expect(await service.getPendingCoverFile(scope, 'book-1'), isNull);
  expect(await service.getCoverFile(scope, 'asset-1'), [4]);
});
```

Extend the worker source assertion to require `bucket` validation and the buckets `cached`, `pending`, and `books`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
cd app
flutter test test/services/book_cover_storage_test.dart test/media/media_storage_scope_test.dart --reporter expanded
```

Expected: FAIL because `localGuest`, pending/guest methods, promotion, and worker bucket handling do not exist.

- [ ] **Step 3: Implement bucketed native and web storage**

Create:

```dart
enum CoverStorageBucket {
  cached('cached'),
  pending('pending'),
  guestBooks('books');

  const CoverStorageBucket(this.pathComponent);
  final String pathComponent;
}
```

Add:

```dart
static const localGuest = MediaStorageScope(profileKey: 'local', userId: 'guest');
```

Route the existing `getCoverFile`, `storeCoverFile`, and `deleteCoverFile` through `CoverStorageBucket.cached`. Add pending and guest wrappers. Native `_coverFile` must build:

```dart
File(p.join(directory.path, bucket.pathComponent, '$id.bin'))
```

and create the bucket directory recursively. Promotion must read pending bytes, atomically store the cached file, and delete pending only after the cached write succeeds.

On web, add `bucket` to `_sendCoverRequest`; the worker must reject values outside:

```javascript
const COVER_BUCKETS = new Set(['cached', 'pending', 'books']);
```

and resolve `media-covers/<scopeKey>/<bucket>/<id>.bin`. Preserve the current copied `ArrayBuffer` transfer so caller bytes are not detached.

- [ ] **Step 4: Run focused tests and worker syntax check**

Run:

```bash
cd app
flutter test test/services/book_cover_storage_test.dart test/media/media_storage_scope_test.dart --reporter expanded
node --check web/book_worker.js
```

Expected: all focused tests pass and Node exits 0.

- [ ] **Step 5: Commit**

```bash
git add app/lib/media/cover_storage_bucket.dart app/lib/media/media_storage_scope.dart app/lib/services/book_import_service_stub.dart app/lib/services/book_import_service.dart app/web/book_worker.js app/test/services/book_cover_storage_test.dart app/test/media/media_storage_scope_test.dart
git commit -m "feat: add pending and guest cover storage"
```

### Task 2: Make queued cover uploads reference pending files

**Files:**

- Modify: `app/lib/media/media_upload_queue.dart`
- Modify: `app/test/media/media_upload_queue_test.dart`

- [ ] **Step 1: Write failing queue persistence and restore tests**

Add:

```dart
test('cover task persists metadata without cover bytes', () async {
  final prefs = await SharedPreferences.getInstance();
  final queue = await _activeQueue(prefs);
  final book = _book(filePath: 'book-1');

  await queue.enqueueCover(book: book, filename: 'cover.jpg', contentType: 'image/jpeg');

  final stored = prefs.getString('media_upload_queue:official--user-1')!;
  expect(stored, isNot(contains('cover_base64')));
  expect(stored, isNot(contains(base64Encode([1, 2, 3]))));
});

test('restored cover task reads pending filesystem bytes', () async {
  final prefs = await SharedPreferences.getInstance();
  final first = await _activeQueue(prefs);
  final book = _book(filePath: 'book-1');
  await first.enqueueCover(book: book, filename: 'cover.jpg', contentType: 'image/jpeg');

  final restored = await _activeQueue(prefs);
  Uint8List? uploaded;
  await restored.processPending(
    dataStore: _dataStoreContaining(book),
    readBookFile: (_) async => null,
    readPendingCover: (_, bookId) async => bookId == book.id ? Uint8List.fromList([1, 2, 3]) : null,
    uploadMedia: (payload) async {
      uploaded = payload.bytes;
      return _asset(assetId: 'cover-1', bookId: book.id, kind: MediaKind.coverImage);
    },
  );
  expect(uploaded, [1, 2, 3]);
});
```

Keep a compatibility test proving an already persisted `cover_base64` task can drain once, but ensure new tasks never serialize that field.

- [ ] **Step 2: Run the queue tests and verify RED**

Run:

```bash
cd app
flutter test test/media/media_upload_queue_test.dart --reporter expanded
```

Expected: FAIL because `enqueueCover` still requires bytes and `processPending` has no `readPendingCover` dependency.

- [ ] **Step 3: Implement metadata-only cover tasks**

Add:

```dart
typedef PendingCoverReader = Future<Uint8List?> Function(MediaStorageScope scope, String bookId);
```

Change new cover enqueueing to omit `coverBase64`. Pass `readPendingCover` into processing and resolve bytes as:

```dart
if (task.kind == MediaKind.coverImage) {
  final legacy = task.coverBase64;
  return legacy == null ? readPendingCover(scope, task.bookId) : base64Decode(legacy);
}
```

Build `toJson()` with conditional entries so `cover_base64` is absent for new tasks. Retain nullable legacy parsing only until existing development queues have drained. Keep the current `_processAgain` behavior and its regression test: a PowerSync callback arriving during a failed upload must trigger a fresh pass.

- [ ] **Step 4: Run queue tests and verify GREEN**

Run:

```bash
cd app
flutter test test/media/media_upload_queue_test.dart --reporter expanded
```

Expected: all queue tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/media/media_upload_queue.dart app/test/media/media_upload_queue_test.dart
git commit -m "fix: queue cover file references instead of bytes"
```

### Task 3: Persist imported covers before saving book metadata

**Files:**

- Create: `app/lib/services/book_import_commit_service.dart`
- Create: `app/test/services/book_import_commit_service_test.dart`
- Modify: `app/lib/widgets/add_book/import_book_sheet.dart`

- [ ] **Step 1: Write failing guest and account commit tests**

Define tests around a small commit service with injected storage callbacks. The account test must assert call order and metadata:

```dart
test('account import stores pending cover and saves no inline cover metadata', () async {
  final calls = <String>[];
  final result = _resultWithCover([1, 2, 3]);
  final service = BookImportCommitService(
    storePendingCover: (_, bookId, bytes) async => calls.add('store:$bookId:${bytes.length}'),
    storeGuestCover: (_, __) async => fail('guest storage must not be used'),
    addBook: (book) async {
      calls.add('book:${book.id}');
      expect(book.coverUrl, isNull);
    },
    enqueueBookFile: (_) async => calls.add('file-task'),
    enqueueCover: (_) async => calls.add('cover-task'),
  );

  await service.commit(result: result, filename: 'book.epub', accountScope: _scope);
  expect(calls, ['store:${result.bookId}:3', 'book:${result.bookId}', 'file-task', 'cover-task']);
});

test('guest import stores permanent local cover without upload tasks', () async {
  final calls = <String>[];
  final result = _resultWithCover([4, 5]);
  final service = BookImportCommitService(
    storePendingCover: (_, __, ___) async => fail('pending storage must not be used'),
    storeGuestCover: (bookId, bytes) async => calls.add('guest:$bookId:${bytes.length}'),
    addBook: (book) async {
      calls.add('book:${book.id}');
      expect(book.coverUrl, isNull);
    },
    enqueueBookFile: (_) async => fail('guest file must not be enqueued'),
    enqueueCover: (_) async => fail('guest cover must not be enqueued'),
  );

  await service.commit(result: result, filename: 'book.epub', accountScope: null);
  expect(calls, ['guest:${result.bookId}:2', 'book:${result.bookId}']);
});
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
cd app
flutter test test/services/book_import_commit_service_test.dart --reporter expanded
```

Expected: compilation fails because `BookImportCommitService` does not exist.

- [ ] **Step 3: Implement the import commit boundary**

The service must:

```dart
final cover = result.coverImage;
if (cover != null) {
  if (accountScope == null) {
    await storeGuestCover(result.bookId, cover);
  } else {
    await storePendingCover(accountScope, result.bookId, cover);
  }
}

final book = Book(
  id: result.bookId,
  title: result.title,
  subtitle: result.subtitle,
  author: result.author,
  coAuthors: result.coAuthors,
  publisher: result.publisher,
  description: result.description,
  language: result.language,
  isbn: result.isbn,
  pageCount: result.pageCount,
  coverUrl: null,
  filePath: localFilePath,
  fileFormat: BookFormat.values.where((value) => value.name == result.fileExtension).firstOrNull,
  fileSize: result.fileSize,
  fileHash: result.fileHash,
  addedAt: now,
);
await addBook(book);
```

Only account mode enqueues book-file and cover tasks. The cover task contains no bytes. Change `_addToLibrary` to `Future<void>`, determine `accountScope` from authenticated mode, and delegate. Remove `bytesToDataUri` from this import path. Guard post-await navigation with `if (!mounted) return`.

- [ ] **Step 4: Run import and queue tests**

Run:

```bash
cd app
flutter test test/services/book_import_commit_service_test.dart test/media/media_upload_queue_test.dart --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/book_import_commit_service.dart app/lib/widgets/add_book/import_book_sheet.dart app/test/services/book_import_commit_service_test.dart
git commit -m "feat: persist imported covers outside metadata"
```

### Task 4: Render pending and guest covers by book ID

**Files:**

- Modify: `app/lib/widgets/book/private_book_cover.dart`
- Modify: `app/lib/widgets/book_details/book_cover_image.dart`
- Modify: `app/lib/data/data_store.dart`
- Modify: `app/lib/models/shelf.dart`
- Modify: all ten production `CoverImage`/`CoverImagePreview` callers found by `rg -n "CoverImage\\(|CoverImagePreview\\(" app/lib`
- Test: `app/test/widgets/book/private_book_cover_test.dart`

- [ ] **Step 1: Write failing fallback-order widget tests**

Add injected local loading to keep tests independent of providers:

```dart
testWidgets('book without media id renders pending local cover', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CoverImage(
      bookId: 'book-1',
      loadLocalBookCover: (_) async => Uint8List.fromList(pngBytes),
      placeholder: const SizedBox(key: Key('placeholder')),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(Image), findsOneWidget);
});

testWidgets('media id takes priority over pending local cover', (tester) async {
  var localLoads = 0;
  var mediaLoads = 0;
  await tester.pumpWidget(MaterialApp(
    home: CoverImage(
      bookId: 'book-1',
      mediaId: 'asset-1',
      loadPrivateCover: (_) async {
        mediaLoads++;
        return Uint8List.fromList(pngBytes);
      },
      loadLocalBookCover: (_) async {
        localLoads++;
        return Uint8List.fromList(pngBytes);
      },
      placeholder: const SizedBox(),
    ),
  ));
  await tester.pumpAndSettle();
  expect(mediaLoads, 1);
  expect(localLoads, 0);
});
```

Retain the legacy inline-data test solely for old rows; new imports are covered by Task 3 and must not create data URIs.

- [ ] **Step 2: Run widget tests and verify RED**

Run:

```bash
cd app
flutter test test/widgets/book/private_book_cover_test.dart --reporter expanded
```

Expected: FAIL because `bookId` and `loadLocalBookCover` are not accepted.

- [ ] **Step 3: Implement local fallback loading and propagate book IDs**

Use this order in `CoverImage`: public/legacy URL, `mediaId` cache/download, then local book cover. Provider loading chooses pending account storage when signed into an account library and guest storage otherwise:

```dart
if (mediaId == null && bookId != null) {
  _coverFuture = isAccountLibrary
      ? importService.getPendingCoverFile(accountScope, bookId)
      : importService.getGuestCoverFile(bookId);
}
```

Add `bookId` to `CoverImagePreview` and `CoverPreview`. Pass `book.id` from book-backed call sites and `cover.bookId` from shelf mosaics/group previews. Include book ID in `_loadKey` so recycled widgets cannot show another book's pending cover.

- [ ] **Step 4: Run widget and representative surface tests**

Run:

```bash
cd app
flutter test test/widgets/book/private_book_cover_test.dart test/widgets/library/book_card_test.dart test/widgets/library/book_list_item_test.dart --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets app/lib/data/data_store.dart app/lib/models app/test/widgets/book/private_book_cover_test.dart
git commit -m "feat: render local covers by book id"
```

### Task 5: Promote source-device covers after upload

**Files:**

- Create: `app/lib/media/cover_upload_persistence.dart`
- Create: `app/test/media/cover_upload_persistence_test.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/media/media_cache_service_test.dart`
- Modify: `app/test/media/media_profile_switch_contract_test.dart`

- [ ] **Step 1: Write a failing promotion orchestration test**

Create `uploadAndPersistCover` in `cover_upload_persistence.dart` so the behavior is testable without constructing `_PapyrusState`:

```dart
test('successful cover upload promotes pending bytes into media cache', () async {
  final calls = <String>[];
  final asset = await uploadAndPersistCover(
    scope: _scope,
    payload: _coverPayload(bookId: 'book-1', bytes: [1, 2, 3]),
    uploadMedia: (_) async => _coverAsset(assetId: 'asset-1', bookId: 'book-1'),
    storeCachedCover: (_, mediaId, bytes) async => calls.add('cache:$mediaId:${bytes.length}'),
    deletePendingCover: (_, bookId) async => calls.add('delete:$bookId'),
  );
  expect(asset.assetId, 'asset-1');
  expect(calls, ['cache:asset-1:3', 'delete:book-1']);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd app
flutter test test/media/cover_upload_persistence_test.dart --reporter expanded
```

Expected: compilation fails because `cover_upload_persistence.dart` and `uploadAndPersistCover` do not exist.

- [ ] **Step 3: Implement best-effort promotion after server success**

Wrap the repository upload used by `_processMediaUploads`. For `MediaKind.coverImage`, atomically store `payload.bytes` under `asset.assetId`, then delete `pending/<book-id>`. A local cache failure must not convert an already successful server upload into a duplicate retry; report it through `FlutterError.reportError` and still return the asset.

The subsequent `_applyUploadedAsset` update sets `coverMediaId`. The source device then reads the promoted cache, while remote devices use the existing `MediaCacheService.ensureCoverCached` download path.

- [ ] **Step 4: Run promotion, profile, queue, and cache tests**

```bash
cd app
flutter test test/media --reporter expanded
```

Expected: all media tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart app/lib/media/cover_upload_persistence.dart app/test/media/cover_upload_persistence_test.dart app/test/media/media_cache_service_test.dart app/test/media/media_profile_switch_contract_test.dart
git commit -m "feat: promote uploaded covers into local cache"
```

### Task 6: Delete every local cover representation

**Files:**

- Modify: `app/lib/services/book_delete_cleanup_service.dart`
- Modify: `app/lib/pages/book_details_page.dart`
- Modify: `app/test/services/book_delete_cleanup_service_test.dart`

- [ ] **Step 1: Write a failing cleanup test**

```dart
test('delete removes pending guest and cached cover files best effort', () async {
  final deleted = <String>[];
  await deleteBookWithMediaCleanup(
    dataStore: dataStore,
    mediaUploadQueue: queue,
    bookId: book.id,
    coverMediaId: 'asset-1',
    deleteBookFile: (_) async {},
    deletePendingCover: (bookId) async => deleted.add('pending:$bookId'),
    deleteGuestCover: (bookId) async => deleted.add('guest:$bookId'),
    deleteCoverFile: (mediaId) async => deleted.add('cached:$mediaId'),
  );
  expect(deleted, ['pending:${book.id}', 'guest:${book.id}', 'cached:asset-1']);
});
```

- [ ] **Step 2: Run cleanup tests and verify RED**

```bash
cd app
flutter test test/services/book_delete_cleanup_service_test.dart --reporter expanded
```

Expected: FAIL because pending and guest deletion callbacks are missing.

- [ ] **Step 3: Implement best-effort cleanup**

Add callbacks for pending and guest files. The page supplies only the callbacks appropriate to its current library mode, but the cleanup service remains idempotent and catches each filesystem failure independently before deleting metadata.

- [ ] **Step 4: Run cleanup and page deletion tests**

```bash
cd app
flutter test test/services/book_delete_cleanup_service_test.dart test/pages/book_details_delete_test.dart --reporter expanded
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/book_delete_cleanup_service.dart app/lib/pages/book_details_page.dart app/test/services/book_delete_cleanup_service_test.dart
git commit -m "fix: clean pending and guest covers on delete"
```

### Task 7: Verify metadata safety, cross-device behavior, and the web runtime

**Files:**

- Test: `app/test/powersync/powersync_book_mapper_test.dart`
- Test: `app/test/services/book_import_commit_service_test.dart`

- [ ] **Step 1: Add the final metadata regression assertion**

Add an assertion to the import commit test and mapper coverage that a newly imported account book serializes with:

```dart
expect(book.coverUrl, isNull);
expect(book.coverMediaId, isNull); // until upload returns an asset
expect(book.toJson().toString(), isNot(contains('data:image')));
```

Also retain the existing test where a row containing only `cover_media_id` is mapped and rendered through the lazy authenticated loader, representing a second device.

- [ ] **Step 2: Run full automated verification**

```bash
cd app
flutter test --reporter expanded
flutter analyze
dart format --output=none --set-exit-if-changed lib test
node --check web/book_worker.js
git diff --check
```

Expected: all tests pass, analysis reports no issues, formatting changes zero files, worker syntax exits 0, and diff check is clean.

- [ ] **Step 3: Perform a clean web restart and manual two-mode smoke test**

Do a full browser reload or restart the Flutter web process so no old PowerSync worker/BroadcastChannel instance remains. Do not use hot reload for this check.

Account flow:

1. Import a covered EPUB while signed in.
2. Confirm the cover remains visible before upload finishes.
3. Confirm the server `books` row is created with `cover_image_url IS NULL`.
4. Confirm `/v1/media` eventually returns 201 and `cover_media_id` becomes non-null.
5. Open the same account in a clean browser profile/device and confirm the first display downloads the cover and a later display uses local OPFS.

Guest flow:

1. Import a covered EPUB in fully offline guest mode.
2. Reload the browser and confirm the cover remains visible from guest OPFS.
3. Sign in and confirm the guest book and cover do not appear in the account library.

Expected: no repeated media 404, no disappearing cover, no newly created `data:image` metadata, and no `LegacyJavaScriptObject` error after a clean worker restart. If the PowerSync type error remains after a clean restart, capture it as a separate dependency/runtime issue rather than masking it in cover code.

- [ ] **Step 4: Commit final regression coverage if Step 1 changed tests**

```bash
git add app/test/powersync/powersync_book_mapper_test.dart app/test/services/book_import_commit_service_test.dart
git commit -m "test: guard filesystem-only cover metadata"
```
