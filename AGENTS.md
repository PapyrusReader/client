# Flutter client

The Flutter package is `app/`, not the repository root. Commands below run from
`app/`; the workspace CLI handles that automatically.

## Code ownership

- `lib/main.dart`: dependency composition and startup.
- `lib/config/app_router.dart`, `lib/pages`, `lib/widgets`: navigation and presentation.
- `lib/providers`: Provider/ChangeNotifier application state.
- `lib/data`: DataStore and repository interfaces; preserve persistence boundaries.
- `lib/powersync`: SQLite schemas, row mapping, local database modes and uploads.
- `lib/auth`: HTTP auth, token storage and configured server URLs.
- `lib/media`, `lib/services`, `lib/acquisition`: caches, import/download workflows and server-managed jobs.
- `lib/opds`: parsing, catalog state, HTTP/relay access and resource caching.
- `lib/reader`: adapts the separately versioned `papyrus_reader` package.
- `lib/themes`, `lib/utils/responsive.dart`: shared design, motion and responsive rules.
- `test`: mirrors domains; `integration_test` contains an opt-in live sync test.

## Implementation

Keep business logic in existing services, repositories and providers. Reuse shared
widgets and theme tokens. Preserve e-ink behavior, keyboard/focus handling, compact
and wide layouts. Use existing platform adapters and conditional imports; do not
introduce unconditional `dart:io` into code that must compile for the web.

Library writes must go through persistence, not only DataStore's in-memory maps.
Guest libraries, signed-in users, different server profiles and their cached
media must stay isolated. Test asynchronous profile switches, offline writes,
logout/reconnect and queued uploads when those paths change.

The client pins `papyrus_reader` to a Git revision in `app/pubspec.yaml`. Editing
the sibling `reader/` checkout does not affect client tests. For coordinated
reader changes, use an ignored `app/pubspec_overrides.yaml` locally, validate both
packages, and update the pinned revision only when the release change is requested.
The current adapter launches EPUB/PDF; README format lists describe broader
product goals and must not be used as proof of implemented reader capabilities.

## Validation

Use the workspace `.fvmrc` SDK via `../tools/flutter` and `../tools/dart` from
the client root, or `../../tools/papyrus` from `app/`.

- Dependencies: `flutter pub get --enforce-lockfile`.
- Formatting: `dart format --output=none --set-exit-if-changed .`.
- Analysis: `flutter analyze --no-fatal-warnings --no-fatal-infos` (same policy as CI).
- Focused tests: `flutter test test/<domain>/<name>_test.dart`.
- Suite/coverage: `flutter test --coverage`.
- Web bootstrap: `node --test test/web/flutter_bootstrap_test.cjs`.
- Web compile for platform-sensitive changes: `flutter build web --dart-define-from-file=.dart_defines`.

Add the narrowest regression for changed behavior. UI changes need a relevant
widget test and visual verification when a running target is available. Analyze
and run relevant tests before broadening to full suites. Report warnings and
unrun platform checks accurately; passing desktop tests alone does not prove web
or mobile behavior. Live sync and OPDS network tests are opt-in and need services.

For auth/sync contract changes, inspect the corresponding server schemas, routes,
services and `powersync/sync-config.yaml`, using the workspace sync-contract skill.
