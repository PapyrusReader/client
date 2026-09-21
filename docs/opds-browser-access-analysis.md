# OPDS browser access: findings and proposed solution

Status: original investigation, superseded by the backend relay implementation on 2026-09-21. Investigated against client commit `bb25365`. Audience: Papyrus maintainers deciding how to support OPDS without requiring accounts.

**Chosen solution: route all OPDS resources through the backend relay.** The user rejected direct/manual downloads. The implementation keeps guest imports local and requires a reachable backend without requiring an account. See [current OPDS behavior and setup](opds-support.md). The evidence below explains the CORS failure; the earlier direct-first proposal is historical and is not the implemented design.

## What fails today

The screenshot is consistent with a confirmed CORS restriction at Project Gutenberg's EPUB endpoints. The catalog itself permits browser access. The download redirects and final book files do not.

Live GET requests with `Origin: http://localhost:8080` returned:

| Gutenberg path | Response | `Access-Control-Allow-Origin` |
|---|---|---|
| `/ebooks/search.opds/` | 200, Atom feed | `*` |
| `/ebooks/1342.opds` | 200, publication entry | `*` |
| `/ebooks/1342.epub3.images` | 302 to `/cache/epub/1342/pg1342-images-3.epub` | Absent |
| `/ebooks/1342.epub.images` | 302 to `/cache/epub/1342/pg1342-images.epub` | Absent |
| Both image EPUB destinations above | 200, EPUB | Absent |
| `/ebooks/1342.epub.noimages` | 302 to `/cache/epub/1342/pg1342.epub` | Absent |
| `/cache/epub/1342/pg1342.epub` | 200, EPUB | Absent |

A separate reproduction in Chrome 153, using a page served on localhost with normal browser security, confirmed:

| Browser request | Observed result |
|---|---|
| Publication feed | Readable 200 response, 12,476 bytes |
| EPUB redirect URL | `TypeError: Failed to fetch` |
| Final EPUB URL directly | `TypeError: Failed to fetch` |
| Final EPUB with `mode: 'no-cors'` | Opaque response, status 0, zero readable bytes |
| Same EPUB through a temporary same-origin relay | Readable 200 response, 558,381 bytes |

This was a transport experiment, not an end-to-end Papyrus import test. The temporary relay was stopped afterwards. The user's exact browser session was not inspected, but the tested endpoints independently reproduce the reported failure.

The existing [transport](../app/lib/opds/opds_http_client.dart) uses direct HTTP requests and browser-managed redirects on web. Public downloads do not add an Authorization header, so removing unnecessary authentication headers would not resolve this case. [Downloads](../app/lib/opds/opds_downloads.dart) need readable bytes before passing the file to the importer. [Import sessions](../app/lib/services/book_import_session.dart) already support guest libraries, and [commit logic](../app/lib/services/book_import_commit_service.dart) queues account uploads only when an account scope exists.

## What browsers can and cannot do

A browser can navigate to a foreign website and save a file without giving Papyrus access to the response bytes. That explains why **Download in browser** works while automatic import fails. The user can subsequently grant access by choosing the saved file through **Add book**.

`no-cors` allows an opaque response; it does not grant readable file contents. Service workers and installed PWAs retain this restriction. Changing Dart libraries, compiling to WebAssembly, using an iframe, or adding CORS headers to Papyrus's own server cannot grant access to Gutenberg's direct responses. The upstream host must allow access, or a permitted intermediary must supply the bytes. See the [Fetch standard](https://fetch.spec.whatwg.org/#concept-filtered-response-opaque) and [MDN's Fetch guidance](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch).

## Viable options

All options below can avoid requiring a Papyrus account.

| Option | Papyrus server needed? | Trade-off |
|---|---|---|
| Direct browser requests | No | Automatic import works with CORS-enabled feeds, files, and redirect chains. Other catalogs remain incompatible. |
| Catalog operator enables CORS, or serves Papyrus under the same origin | No separate Papyrus backend | Good for catalogs under the operator's control; requires cooperation for third-party hosts. |
| Browser download followed by file import | No | Works with accessible downloads, but requires manual save and import. Already supported. |
| Optional anonymous relay | Yes, a small relay | Automatic import for supported public resources despite missing upstream CORS. Adds bandwidth costs and an operational dependency. |
| Native app or browser extension | No Papyrus relay | Native HTTP avoids browser CORS. An extension needs installation and host permissions; it is a separate distribution and trust model. |

Chrome documents the extension exception in [cross-origin network requests](https://developer.chrome.com/docs/extensions/develop/concepts/network-requests). It does not apply to ordinary web pages or extension content scripts without the appropriate privileged request path.

## Original proposal (superseded)

Keep catalog transport separate from library ownership and synchronization:

```text
Papyrus browser → catalog directly → readable bytes → local import
       │
       └─ eligible transport failure → optional relay → catalog
                                           │
                                           └─ readable bytes → same local import
```

1. Add relay support at the `OpdsHttpClient` boundary so it can serve feeds, OpenSearch descriptions, covers, and books. Fixing downloads alone addresses Gutenberg today but leaves catalogs whose feeds block CORS unsupported.
2. Try direct requests first. In web builds, retry an eligible connection failure once through a configured relay. Browser errors cannot reliably distinguish CORS from connectivity, so do not label every failure as confirmed CORS. Do not retry cancellations, invalid files, or readable authentication failures through another transport.
3. Make relay configuration independent of login and the sync-server selection. The hosted app can provide an anonymous default for supported public catalogs; self-hosted deployments can provide their own endpoint. Static deployments without a relay retain direct access and manual import.
4. Stream the upstream response back to the browser and reuse the existing import session. No account, database record, server-side book library, or persistent file storage is required for relaying. Preserve cancellation, progress, and the existing protection against committing into a different library after an account switch.
5. Return the final upstream URL alongside the content type and binary body. The parser uses `response.uri` to resolve relative links; using the relay URL would break navigation, search, and covers. Follow redirects inside the relay instead of redirecting the browser back to the blocked resource. A separately hosted relay must permit the app's origin and expose the necessary response metadata.

For the first version, implement an anonymous public-catalog relay endpoint in the existing FastAPI backend, with no user/session or database dependency in its request path. The frontend may use it while remaining in guest mode. A standalone edge function is also viable if deploying the full Papyrus backend is undesirable; it remains server-side infrastructure, even if marketed as “serverless.” Hosting choice and bandwidth budget remain deployment decisions.

Start with explicitly supported public hosts and paths, including Gutenberg's catalog and acquisition resources. Revalidate every redirect and actual network destination, blocking private, loopback, link-local, and metadata addresses, including DNS-rebinding routes. Apply request/concurrency limits, timeouts, redirect limits, and enforced byte limits while streaming. CORS origin checks alone do not prevent relay abuse. Preserve the current client limits of 8 MiB for catalog resources and 256 MiB for books as upper bounds, with deployment quotas allowed to be lower. Treat relayed content as data; do not serve arbitrary upstream HTML as an executable page on the app origin.

Keep authenticated catalogs direct initially. Supporting them through a relay later means trusting that relay with catalog credentials and download URLs; it should be explicit, scoped to the catalog origin, and excluded from shared caches and credential-bearing logs. Never forward Papyrus account tokens upstream. Private LAN catalogs need direct access or a deliberately configured local relay reachable from that network. A relay does not bypass catalog authentication, DRM, or upstream availability restrictions.

## Original verification proposal (superseded)

Before shipping, verify guest browsing and EPUB import with the backend's account and sync services unused; direct success without relay traffic; blocked feeds and blocked downloads through the relay; relative links after upstream redirects; cancellation and library switching; size limits and rejected redirect destinations. Use controlled CORS fixtures for regression tests and Gutenberg only for an occasional compatibility check.

In the chosen implementation, disabling the relay makes OPDS unavailable; there is no direct-fetch or manual-download fallback. [OPDS support documentation](opds-support.md) describes the current behavior.
