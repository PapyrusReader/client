# Web hot restart

Papyrus performs a full browser refresh when Flutter requests a web hot restart
(`R` in the development terminal). Normal hot reload (`r`) is unchanged.

## Why the previous startup failed

The old web cleanup helper stored a Dart callback on `window`, then called it
from the next invocation of `main()`. By that point, hot restart had already
reset Dart's runtime types. PowerSync/SQLite worker messages and other browser
callbacks could still reach objects from the previous runtime. This produced
type errors involving `LegacyJavaScriptObject`, update notifications, and
Flutter diagnostics.

Cleanup was awaited before `runApp()`. When it failed, startup stopped, leaving
a blank page. The callback was cleared before invocation, which explains why a
second restart could succeed. A unit test calling cleanup twice within a single
Dart runtime could not detect this failure.

## Current behavior

`app/web/flutter_bootstrap.js` uses Flutter's documented
[`onEntrypointLoaded` callback](https://docs.flutter.dev/platform-integration/web/initialization#the-onentrypointloaded-callback),
which runs on initial loading and each hot restart. Its JavaScript state survives
a Dart restart. The second entrypoint invocation reloads the document instead of
initializing another Dart runtime alongside stale browser listeners.

This retains the current URL and browser storage, including the offline library.
It does not clear databases or other tabs. Normal widget disposal still closes
the app's data services; no Dart cleanup closure is retained across restarts.

Refresh the browser once after installing this change so the page loads the new
bootstrap. Subsequent terminal restarts refresh automatically. Flutter's debugger
may log `Cannot find context with specified id` during reconnection to the new
document; this is separate from the previous Dart startup failure and did not
prevent the app from rendering in validation.

## Verification

- Reproduced stale-runtime errors and a blank first restart in an isolated Chrome
  session before the change.
- Created a physical book in an offline library, then performed three consecutive
  terminal hot restarts. Each returned to `/library/books`, rendered the saved
  book, and preserved a browser-storage marker without a second restart.
- Normal hot reload retained the same browser document and rendered library.
- Four bootstrap tests passed, covering cold startup, repeated restarts, a fresh
  document, and a restart during initialization.
- 37 relevant PowerSync, auth, and composition tests passed; one case was skipped
  by the existing test configuration. Flutter analysis and the
  production web build passed.

Run the bootstrap tests from `app/`:

```sh
node --test test/web/flutter_bootstrap_test.cjs
```
