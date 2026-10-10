# PDF import validation — 2026-10-10

Native PDF import and the EPUB/PDF reader already existed. Browser imports were
restricted to EPUB in both the picker and the import service. Web imports now
accept PDF; the same allowlist also enables PDF acquisitions from OPDS catalogs.

PDF metadata extraction is shared by native and browser import paths using the
existing Syncfusion dependency. It reads title, author, subject and page count,
with the filename as the title fallback. The browser worker hashes the original
bytes and stores them in OPFS before the normal library commit. Selected bytes
are retained for failed-import retries. The worker URL has a protocol revision
so existing clients do not keep using a cached EPUB-only worker.

PDF parsing runs in Dart; hashing and browser storage run in the import worker.
No new runtime downloads, dependencies, database/locator schemas or release pins
were introduced. Password entry during import and generated PDF cover thumbnails
are not implemented; PDFs without a cover use the existing library placeholder.

## Verification

- 98 focused client tests passed, including shared PDF metadata, native file
  storage/hash/reload/delete, filename fallback, malformed input, worker storage
  errors, import UI/controller/commit and reader locator/session tests.
- Eight pre-existing metadata tests skipped because their local EPUB/MOBI
  fixtures were unavailable. The new PDF tests did not skip.
- Client analysis, formatting/bootstrap checks and production web build passed.
- Actual desktop Chrome: selected a PDF through Add book → Import digital books,
  imported it, checked metadata, opened its rendered pages, turned pages, sought
  to page 435, left the reader, restarted the app and resumed at page 435 (49%).
- Native import storage was checked with Flutter tests. A new native-device PDF
  picker session and authenticated server synchronization were not run.

The real-book browser input was [Structure and Interpretation of Computer
Programs, second edition](https://web.mit.edu/6.001/6.037/sicp.pdf), hosted by MIT:
883 pages, approximately 7.1 MiB. SHA-256:

```
08709a87567d8311d6fd29c4f4a5386801153e71450e628c4a5a5d7e85feda8b
```

The downloaded book, screenshots and logs remain local under ignored
`app/build/pdf-validation/`; the PDF is not committed.

From `client/app`, using the workspace-pinned Flutter SDK and ignored local reader
override:

```sh
../../tools/flutter test test/services/pdf_book_import_test.dart \
  test/services/file_metadata_service_test.dart \
  test/services/book_cover_storage_test.dart \
  test/services/book_import_commit_service_test.dart \
  test/widgets/add_book test/reader/reader_book_adapter_test.dart \
  test/reader/reader_session_test.dart
../../tools/flutter build web --no-pub
```
