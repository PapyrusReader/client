# OPDS support

Papyrus browses OPDS 1.2 (Atom/XML) and OPDS 2.0 (JSON) catalogs through its backend relay and imports book downloads automatically into the active library. A running Papyrus backend is required; a Papyrus account is not.

## Using catalogs

1. Open **Library → Catalogs**. On a narrow screen, open **Library sections** first.
2. Select **Add catalog** and enter a name and the catalog's HTTP or HTTPS URL. Enter a username and password if the catalog uses HTTP Basic authentication.
3. Open the catalog, browse its sections or use keyword search, and select a publication to open its book details page. Switch between cover grids and lists using the view control. Details preserve description paragraphs and can be refreshed or opened directly from their URL. Back returns through each visited feed, edition selection and details page, preserving search, scroll position and view mode. A shared subsection with no prior visit returns to its catalog's root, then to all catalogs. Browser URLs continue to identify the visible feed or publication.
4. Select **Add to library** to open the download-options sheet, then choose a supported format. The **Downloads** control in the page header opens progress, cancellation, retry, and completed transfers. Downloads continue when you close a sheet or navigate elsewhere in Papyrus. Use **Open book** after the import finishes.

Catalog creation, settings, removal confirmation, download options, and transfer activity use bottom sheets on all screen sizes. Forms keep their actions above the keyboard; catalog and book lists use the library's page alignment and theme.

Web imports support EPUB. Native imports support EPUB, PDF, MOBI, AZW3, TXT, CBZ, and CBR, matching the existing file importer. The short final **Adding to library** step cannot be cancelled; earlier download and processing steps can. Failed downloads offer Retry.

Catalog settings stay on this device, separately for each server/account and for the guest library. Credentials are stored through the platform's secure-storage implementation, separately from catalog preferences and bound to the catalog origin. Removing a catalog also removes its credentials; downloaded books remain in your library. On an existing catalog, leave the credentials blank to retain them, or select **Remove saved credentials**. Changing its URL origin clears saved credentials unless replacement credentials are entered.

Imported books use the existing local file storage, metadata persistence, cover handling, and media-upload queue. Embedded book metadata takes precedence; catalog metadata fills missing values. Signed-in libraries retain their existing synchronization behavior. Switching accounts invalidates in-flight OPDS work before it can import into the newly selected library.

## Previously imported books and saved catalog content

After a successful import, publications show **In library** and their details offer **Open book**, including after restarting Papyrus. **Download options** remains available for other formats. Recognition uses the saved catalog, source URL, exact publication identifier and acquisition URL; matching titles or ISBNs never combine editions. Samples do not mark the full publication as imported. Removing a book from the active library makes it downloadable again.

Recognition is local to this device and library account, including the guest library. Older imports and manually added books have no OPDS provenance and are not matched automatically. Renaming a catalog preserves recognition; removing it, changing its source URL, or replacing/removing its credentials clears that catalog's recognition without deleting any books.

Previously visited feeds appear immediately and refresh through the relay in the background. If refreshing fails, Papyrus keeps saved content visible with a retry notice. Previously cached publication details can also open from their URLs offline. Cached cover images are reused for up to one day before refreshing. Offline browsing covers saved pages only; new searches/pages and book downloads still need a connection, though saved search descriptions can resolve previously visited search URLs.

The response cache is shared across scopes with a total serialized limit of 2 MiB, 64 entries, and 512 KiB per entry. Least recently used entries are evicted; larger responses still load online but are not saved. The cache retains response bytes, final URLs, timestamps and content types, never authorization headers or passwords. It does not cache book files. Account switching hides other accounts' content; source/credential edits, removal and authorization failures invalidate affected cached content and outstanding requests. Corruption or unavailable browser storage does not block browsing or importing.

## Compatibility and troubleshooting

- Feeds, search descriptions, covers, and book files all pass through the selected Papyrus backend. Catalogs do not need browser CORS support. The app must be able to reach its backend, whose `CORS_ORIGINS` must allow the web app. Use an HTTPS backend when hosting the web app over HTTPS.
- Authentication supports HTTP Basic. The selected backend receives catalog credentials for the request and forwards them only to that catalog's origin. Use a trusted backend and HTTPS for the backend and protected catalog. Papyrus account tokens and browser cookies are never forwarded upstream.
- The relay only permits public network destinations. Loopback, private LAN, link-local, and metadata-service addresses are rejected, including after redirects. Administrators can further restrict catalog hosts. Private LAN catalogs are not supported by this relay.
- Browsing includes groups, facets, pagination, complete publication entries, and advertised keyword search. OPDS 1.2 uses OpenSearch descriptions; OPDS 2.0 uses URI templates.
- Purchases, loans, subscriptions, DRM, indirect acquisition, and OAuth are displayed as unsupported acquisition methods. Papyrus does not follow those links as book downloads.
- Catalog settings, import recognition and cached catalog content do not sync between devices. Downloads do not resume after the app closes.
- Feed, search-description, and image responses are limited to 8 MiB; book downloads to 256 MiB. DNS and opening a response each have a 30-second limit, stalled reads time out after 30 seconds, and each upstream request has a five-minute total deadline. These limits protect the current in-memory import pipeline.
- The client queues excess requests and briefly retries temporary relay-capacity errors. Authentication errors offer guidance to edit catalog credentials. Other failures remain in the download panel with Retry; no manual save-and-import step is required.

### Server setup

The official backend comes from `PAPYRUS_API_BASE_URL` (default `http://localhost:8080`). Selecting a custom server uses that server's relay, including in guest mode. Deploy the updated client and backend together. If OPDS requests return 404, update the backend and check its API prefix and reverse-proxy routing.

The relay is enabled by default. Operators can disable it with `OPDS_RELAY_ENABLED=false` or restrict destinations using `OPDS_RELAY_ALLOWED_HOSTS`, a JSON list of exact hostnames. All redirect and image/CDN hosts must also be permitted. An empty list allows public hosts. Guest imports stay local; relaying does not create an account or upload the guest library.

## Implementation

Catalog book details share the library's section headings, description typography and metadata rows. Description and Information use two columns when space permits, and stack on mobile; subjects are read-only chips. The parser retains available publication dates, page counts, rights and subjects. Atom entry timestamps are not treated as publication dates.

For catalogs hosted on `gutenberg.org` or its subdomains, a presentation adapter recognizes Gutenberg's labeled description paragraphs. Summary, edition prose, credits, notes and unfamiliar paragraphs appear in Description. Metadata, including reading level and classification, appears in Information; conflicting values remain visible in the corresponding row. Subject chips exclude classification and category labels already shown in Information. All content is visible without expanding a section. The original description remains unchanged in the publication model. Other catalogs retain their supplied descriptions without this extraction.

The `lib/opds` module separates normalized models, XML/JSON parsing, search expansion, scoped persistence, HTTP transport, browsing state, and application-scoped downloads. `BookImportSession` captures the existing import destination and supplies the shared `BookImportCommitService` composition used by OPDS and file-import widgets.

The routes `/library/catalogs` and `/library/catalogs/:catalogId` live inside the existing Library shell. The `feed` query parameter stores the current resource URL, and `q` retains the displayed keyword query. Neither contains Basic credentials. Browser history and refresh reload the selected feed.

`OpdsHttpClient` posts resource URLs and optional catalog credentials to `/v1/opds/relay`. It reads the final upstream URL from `X-OPDS-URL` so relative links resolve against the catalog. The backend streams bytes without storing books. No database schema or dependency changes are required.

## Verification

From `client/app`, run:

```sh
flutter test --coverage
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
flutter build web --no-pub
flutter build linux --no-pub
```

Network smoke tests use a local fixture server that emulates the relay contract for its own loopback resources. These tests are skipped in the normal suite. Start it in a separate terminal:

```sh
python3 tool/opds_fixture_server.py --port 8766
```

Then run the same tests on the Linux Dart VM and Chrome:

```sh
flutter test test/opds/network_smoke_test.dart --no-pub --dart-define=OPDS_SMOKE_URL=http://127.0.0.1:8766
flutter test test/opds/network_smoke_test.dart --no-pub --platform chrome --dart-define=OPDS_SMOKE_URL=http://127.0.0.1:8766
```

The fixtures cover public and Basic-auth catalogs in both formats, browsing, details, search, pagination, EPUB bytes, redirect URL resolution, authentication failures, and cross-origin credential stripping. They use the test credentials `reader` / `secret` and bind only to localhost.

The smoke suite checks that missing CORS headers on upstream redirects and book responses do not prevent relay downloads on Chrome or native platforms. The catalog at `/public/v2/blocked.json` exercises this flow.

For visual fixture checks, launch the client with `--dart-define=PAPYRUS_API_BASE_URL=http://127.0.0.1:8766` and add `http://127.0.0.1:8766/public/v2/showcase.json` as a catalog. This fixture includes books, covers, sections, and long descriptions. Replace `public` with `protected` to check Basic authentication. This loopback exception exists only in the fixture server; the production backend rejects these destinations.

### Relay verification — 2026-09-21

- 93 Flutter OPDS tests passed, including ten native fixture network tests.
- 30 Chrome network, relay-contract, and presentation tests passed.
- 48 backend tests passed, including destination/deadline/cleanup coverage and health-route regression tests. Ruff and scoped mypy passed.
- Flutter analysis and the production web build passed.
- Chrome fetched Gutenberg's OPDS entry and a complete 558,381-byte EPUB through the actual FastAPI relay without account authentication. The client import pipeline is covered by download regression tests; this live browser check verified transport, not a full interactive app import.
- The updated client and backend must be deployed together. No deployment was performed during this verification.

### Original implementation verification — 2026-09-06

- Full Flutter suite: 1,222 passed, 18 skipped (including the eight opt-in network smoke tests).
- Real HTTP smoke suite: eight passed on the Linux Dart VM and eight passed in Chrome.
- Flutter analysis: no issues. Formatting verification: 406 Dart files checked, no changes. Git whitespace check passed.
- Web and Linux production builds passed.
- Built web application: verified guest catalog browsing and EPUB download/import into the library, then entered Basic credentials through the catalog editor and browsed the protected catalog. Visually checked the redesigned desktop and phone layouts. Regression tests cover light, dark, and e-ink themes, grid/list switching, aligned covers, pagination, expandable descriptions, transfer controls, and opening the keyboard while transfers are expanded.
- Independent specification and code reviews completed; their credential, account-transition, facet, search, response-validation, and cancellation findings were fixed and covered by regression tests.
