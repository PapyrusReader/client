# OPDS Relay Implementation Plan

**Goal:** Route OPDS browsing and automatic library imports through the Papyrus backend, including guest use.

**Architecture:** The client posts resource requests to the selected backend's `/v1/opds/relay`. An anonymous, rate-limited endpoint streams resources from validated public destinations. Catalog credentials stay scoped to their origin; final upstream URLs preserve relative links. The existing local import pipeline owns library writes.

**Tech stack:** FastAPI, Python standard-library HTTP/TLS with pinned destination addresses, Flutter's existing HTTP client. No new dependencies or database schema changes.

- [x] Add failing backend route/service tests for anonymous streaming, redirects, origin-scoped authentication, public destination validation, response limits, errors, and cleanup.
- [x] Implement request schema, bounded relay service, thin route, router registration, and exposed CORS metadata. Use existing rate limiting. Validate each destination and connect to the checked IP while preserving TLS hostname verification.
- [x] Replace client direct requests with relay POSTs; test the request contract, final URLs, errors, progress, cancellation, and no outbound account tokens.
- [x] Share the configured transport between catalog browsing and downloads. Remove manual browser-download recovery from the UI and adjust regression coverage.
- [x] Update operator/client documentation and the earlier analysis to reflect the user's chosen backend relay design.
- [x] Run focused Python and Flutter tests, lint/type checks, and a live Gutenberg relay smoke test. Review resource cleanup, redirect validation, and guest composition before completion.

Validation commands: `uv run pytest tests/services/test_opds.py tests/api/routes/test_opds.py`; `uv run ruff check` and `uv run mypy` on changed backend modules; `flutter test test/opds --no-pub`; `flutter analyze` on changed client code. Changes remain in the current checkout for review.

Verified: 48 backend tests including health-route regression tests; 93 Flutter OPDS tests including ten native network smoke cases; 30 Chrome network/transport/presentation tests. Ruff, scoped mypy, Flutter analysis, and the production web build passed. Chrome retrieved Gutenberg's publication entry and a complete 558,381-byte EPUB through the actual anonymous FastAPI relay. Independent review found deadline and cover-concurrency issues, both fixed and covered by regression tests. No deployment was performed.
