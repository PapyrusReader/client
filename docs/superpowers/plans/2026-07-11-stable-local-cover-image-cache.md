# Stable Local Cover Image Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate cover flashes between Papyrus pages by giving filesystem-backed covers stable Flutter image-cache identities.

**Architecture:** Add a `LocalCoverImageProvider` whose immutable key contains storage scope, bucket, and file ID. `PrivateBookCover` will resolve local account, pending, and guest covers through that provider so Flutter's bounded global `ImageCache` reuses decoded frames across widget instances; OPFS/native files remain authoritative and existing authenticated lazy download remains the cached-media loader.

**Tech Stack:** Flutter/Dart, `ImageProvider`, `MultiFrameImageStreamCompleter`, Flutter `ImageCache`, native filesystem, browser OPFS, widget/unit tests.

---

## File structure

- Create `app/lib/media/local_cover_image_provider.dart`: stable cover key, asynchronous byte decoding, and targeted cache eviction.
- Create `app/test/media/local_cover_image_provider_test.dart`: key isolation, loader reuse, failures, and eviction.
- Modify `app/lib/widgets/book/private_book_cover.dart`: replace provider-backed `FutureBuilder` reads with stable local image providers while retaining public and injected compatibility paths.
- Modify `app/test/widgets/book/private_book_cover_test.dart`: verify separately mounted library/details widgets reuse the decoded image without another storage read or placeholder frame.
- Modify `app/lib/services/book_import_service.dart`: evict web cover keys when same-identity files are overwritten or deleted.
- Modify `app/lib/services/book_import_service_stub.dart`: matching native eviction behavior.
- Modify `app/test/services/book_cover_storage_test.dart`: verify storage replacement and deletion invalidate decoded keys.

### Task 1: Add a stable filesystem-backed cover image provider

**Files:**
- Create: `app/lib/media/local_cover_image_provider.dart`
- Create: `app/test/media/local_cover_image_provider_test.dart`

- [ ] **Step 1: Write failing provider cache-key tests**

Create tests around a valid one-pixel PNG and clear `PaintingBinding.instance.imageCache` in setup/teardown:

```dart
testWidgets('equal local cover keys reuse one filesystem load', (tester) async {
  var loads = 0;
  Future<Uint8List?> load() async {
    loads++;
    return pngBytes;
  }

  final first = LocalCoverImageProvider(
    scopeKey: 'official--user-1',
    bucket: CoverStorageBucket.cached,
    fileId: 'asset-1',
    loadBytes: load,
  );
  final second = LocalCoverImageProvider(
    scopeKey: 'official--user-1',
    bucket: CoverStorageBucket.cached,
    fileId: 'asset-1',
    loadBytes: load,
  );

  await tester.pumpWidget(MaterialApp(home: Image(image: first)));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(MaterialApp(home: Image(image: second)));
  await tester.pumpAndSettle();

  expect(loads, 1);
});

test('scope bucket and file id participate in key equality', () {
  expect(_provider(scope: 'one', bucket: CoverStorageBucket.cached, id: 'x').key,
      isNot(_provider(scope: 'two', bucket: CoverStorageBucket.cached, id: 'x').key));
  expect(_provider(scope: 'one', bucket: CoverStorageBucket.cached, id: 'x').key,
      isNot(_provider(scope: 'one', bucket: CoverStorageBucket.pending, id: 'x').key));
  expect(_provider(scope: 'one', bucket: CoverStorageBucket.cached, id: 'x').key,
      isNot(_provider(scope: 'one', bucket: CoverStorageBucket.cached, id: 'y').key));
});
```

Add tests that null bytes report an image-stream error and `evict` causes the next equal provider to invoke its loader again.

- [ ] **Step 2: Run the provider test and verify RED**

Run:

```bash
cd app
flutter test test/media/local_cover_image_provider_test.dart --reporter expanded
```

Expected: compilation fails because `LocalCoverImageProvider` does not exist.

- [ ] **Step 3: Implement the stable key and provider**

Create an immutable key and provider using Flutter 3.41's `loadImage` API:

```dart
@immutable
class LocalCoverImageKey {
  const LocalCoverImageKey({required this.scopeKey, required this.bucket, required this.fileId});

  final String scopeKey;
  final CoverStorageBucket bucket;
  final String fileId;

  @override
  bool operator ==(Object other) =>
      other is LocalCoverImageKey &&
      other.scopeKey == scopeKey &&
      other.bucket == bucket &&
      other.fileId == fileId;

  @override
  int get hashCode => Object.hash(scopeKey, bucket, fileId);
}

class LocalCoverImageProvider extends ImageProvider<LocalCoverImageKey> {
  LocalCoverImageProvider({
    required String scopeKey,
    required CoverStorageBucket bucket,
    required String fileId,
    required this.loadBytes,
  }) : key = LocalCoverImageKey(scopeKey: scopeKey, bucket: bucket, fileId: fileId);

  final LocalCoverImageKey key;
  final Future<Uint8List?> Function() loadBytes;

  @override
  Future<LocalCoverImageKey> obtainKey(ImageConfiguration configuration) => SynchronousFuture(key);

  @override
  ImageStreamCompleter loadImage(LocalCoverImageKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: key.toString());
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await loadBytes();
    if (bytes == null || bytes.isEmpty) throw StateError('Local cover file was not found');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  static bool evictKey({required String scopeKey, required CoverStorageBucket bucket, required String fileId}) {
    return PaintingBinding.instance.imageCache.evict(
      LocalCoverImageKey(scopeKey: scopeKey, bucket: bucket, fileId: fileId),
      includeLive: true,
    );
  }
}
```

Implement `toString` for diagnostics. Keep the loader out of equality so new widget instances with the same storage identity share Flutter's cache entry.

- [ ] **Step 4: Run provider tests and analysis**

Run:

```bash
cd app
flutter test test/media/local_cover_image_provider_test.dart --reporter expanded
flutter analyze
```

Expected: all provider tests pass and analysis reports no issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/media/local_cover_image_provider.dart app/test/media/local_cover_image_provider_test.dart
git commit -m "feat: add stable local cover image provider"
```

### Task 2: Render production local covers through Flutter's image cache

**Files:**
- Modify: `app/lib/widgets/book/private_book_cover.dart`
- Modify: `app/test/widgets/book/private_book_cover_test.dart`

- [ ] **Step 1: Write the failing cross-page reuse test**

Extend the provider harness with `Provider<BookImportService>` and `Provider<MediaCacheService>`. Use a recording import service whose cached-cover loader returns valid PNG bytes. Mount a library-style cover, unmount it, and mount a details-style cover with the same book/media identity:

```dart
testWidgets('new page reuses decoded private cover without reading storage again', (tester) async {
  final harness = await _buildProviderHarness();
  final importService = _RecordingCoverImportService(pngBytes);

  Widget page(Key key) => harness.wrapWithCoverServices(
    PrivateBookCover(
      key: key,
      bookId: 'book-1',
      mediaId: 'asset-1',
      placeholder: const SizedBox(key: Key('placeholder')),
    ),
    importService: importService,
  );

  await tester.pumpWidget(page(const Key('library-cover')));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(page(const Key('details-cover')));
  await tester.pump();

  expect(find.byKey(const Key('placeholder')), findsNothing);
  expect(importService.cachedReads, 1);
});
```

Add equivalent tests for pending account and guest keys, plus a profile-key change test proving it performs a new read.

- [ ] **Step 2: Run the widget test and verify RED**

Run:

```bash
cd app
flutter test test/widgets/book/private_book_cover_test.dart --reporter expanded
```

Expected: the second widget performs another asynchronous storage read and exposes the placeholder during its first frame.

- [ ] **Step 3: Route provider-backed sources through `LocalCoverImageProvider`**

Retain the current injected-loader `FutureBuilder` path for isolated tests and compatibility. Add `_localImageProvider` and configure it for production sources:

```dart
_localImageProvider = LocalCoverImageProvider(
  scopeKey: scope.persistenceKey,
  bucket: CoverStorageBucket.cached,
  fileId: mediaId,
  loadBytes: () => cacheService.ensureCoverCached(
    scope: scope,
    mediaId: mediaId,
    readLocalCover: importService.getCoverFile,
    writeLocalCover: importService.storeCoverFile,
    downloadMedia: authProvider.downloadMedia,
  ),
);
```

Use `CoverStorageBucket.pending` with `getPendingCoverFile` for account book-ID covers and `CoverStorageBucket.guestBooks` with `MediaStorageScope.localGuest.persistenceKey` for guest covers.

Render the provider with the existing placeholder contract:

```dart
return Image(
  image: provider,
  fit: widget.fit,
  gaplessPlayback: true,
  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
    return wasSynchronouslyLoaded || frame != null ? child : widget.placeholder;
  },
  errorBuilder: (_, _, _) => widget.placeholder,
);
```

Clear `_localImageProvider` whenever book ID, media ID, URL, injected loader, auth mode, or profile scope changes. Public URLs and legacy inline data remain unchanged.

- [ ] **Step 4: Run cover and representative surface tests**

Run:

```bash
cd app
flutter test \
  test/widgets/book/private_book_cover_test.dart \
  test/widgets/library/book_card_test.dart \
  test/widgets/library/book_list_item_test.dart \
  test/widgets/book_details/book_cover_image_test.dart \
  --reporter expanded
```

Expected: all tests pass, including one storage read across separately mounted pages.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/book/private_book_cover.dart app/test/widgets/book/private_book_cover_test.dart
git commit -m "fix: reuse decoded covers across page transitions"
```

### Task 3: Invalidate decoded covers when local files are removed

**Files:**
- Modify: `app/lib/services/book_import_service.dart`
- Modify: `app/lib/services/book_import_service_stub.dart`
- Modify: `app/test/services/book_cover_storage_test.dart`

- [ ] **Step 1: Write failing invalidation tests**

Populate `PaintingBinding.instance.imageCache` with a `LocalCoverImageProvider`, then delete the corresponding filesystem cover. Resolve an equal provider again and assert the loader runs a second time. Cover cached, pending, and guest identities; also assert promotion evicts the pending book-ID key.

- [ ] **Step 2: Run storage tests and verify RED**

Run:

```bash
cd app
flutter test test/services/book_cover_storage_test.dart --reporter expanded
```

Expected: cached decoded entries survive filesystem deletion and the loader is not called again.

- [ ] **Step 3: Evict deterministic keys after successful removal**

After successful store/delete operations, call:

```dart
LocalCoverImageProvider.evictKey(
  scopeKey: scope.persistenceKey,
  bucket: bucket,
  fileId: id,
);
```

Promotion evicts `pending/<book-id>` after the cached write succeeds. Do not evict after ordinary store operations: a lazy authenticated download stores the same key that is currently resolving, and evicting it would defeat reuse on the next page. Cover replacement already receives a new media ID. Apply matching deletion and promotion behavior to web and native services. Filesystem failure must not evict a still-valid decoded image.

- [ ] **Step 4: Run storage, media, and cover tests**

Run:

```bash
cd app
flutter test test/services/book_cover_storage_test.dart test/media test/widgets/book/private_book_cover_test.dart --reporter expanded
flutter analyze
node --check web/book_worker.js
```

Expected: all tests pass, analysis is clean, and worker syntax remains valid.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/book_import_service.dart app/lib/services/book_import_service_stub.dart app/test/services/book_cover_storage_test.dart
git commit -m "fix: evict decoded covers after local mutation"
```

### Task 4: Final verification and browser smoke test

**Files:**
- No production files expected beyond Tasks 1-3.

- [ ] **Step 1: Run complete automated verification**

```bash
cd app
flutter test --reporter compact
flutter analyze
dart format --output=none --set-exit-if-changed lib test
node --check web/book_worker.js
git diff --check
```

Expected: all tests pass, analysis reports no issues, formatting changes zero files, JavaScript syntax is valid, and the diff check is clean.

- [ ] **Step 2: Perform live navigation verification**

With a signed-in library containing a covered book:

1. Open the library grid and wait for the cover to render once.
2. Open book details and confirm the cover appears without a placeholder flash.
3. Navigate back to the library and confirm the same behavior.
4. Switch between grid and list layouts and confirm no storage reread for the same key.
5. Repeat with a guest book after a first render.

Use the existing CDP cover trace to confirm subsequent mounts do not issue another `getCover` request for an image still held by Flutter's image cache.

- [ ] **Step 3: Review branch state**

```bash
git status --short --branch
git log --oneline -8
```

Expected: the worktree is clean and the new commits are present on `codex/media-storage-pipeline`.
