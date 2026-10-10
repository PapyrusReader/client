# Delivery rollout evidence

Status recorded on 2026-10-11. This is an implementation checkpoint, not a claim
that the new release process has delivered a working release to every platform.
Version numbers have not changed and no release has been published by this work.

## Configured

- GitHub `release` environment contains the separate web deployment SSH secret
  and host/user/known-host variables.
- The web host uses versioned directories and `current`; the previous flat files
  were preserved during migration. Caddy was reloaded without restarting API,
  PowerSync or database containers.
- `/` and `/login` still serve the existing app with revalidation headers. The
  restricted SSH receiver rejects invalid commands and a checksum mismatch
  without changing the active release.
- The dedicated Play service account and its JSON key have been created. The key
  is stored as `PLAY_SERVICE_ACCOUNT_JSON` in GitHub's `release` environment.
  No Google Cloud project roles were granted.
- The Android Publisher API is enabled. Play access is active for only
  `com.papyrus.reader`, with app visibility and testing-release permission;
  production, finance, administration and tester-list management are ungranted.
- A live API probe created and deleted an inspection edit successfully. Build 1
  is completed on `internal`, with no production/alpha/beta releases. Its bundle
  SHA-256 matches the existing GitHub `v0.0.1+1` AAB, and the retry preflight
  returns `complete` without changing any track. The temporary local JSON key
  was removed after verification.

## Local verification

- 35 client release-tool tests, 22 server tooling tests and 18 workspace tooling
  tests pass. Checks cover release gates, tag/version identity, checksums, unsafe
  archives, immutable publication, retry behavior, web rollback and migration.
- Client formatting/analysis/web bootstrap checks, workflow lint, shell lint,
  deployment-layout checks and website tests/build pass.
- Linux tar, `.deb` and AppImage assembly was exercised with the existing
  `v0.0.1+1` Linux binary as a fixture, on Ubuntu 24.04 x64 under macOS emulation.
  This is not a build of the current client revision.
- The `.deb` installed, reinstalled and uninstalled successfully; its desktop
  launcher validates and a user-data sentinel survives removal.
- The extracted AppImage starts, and its bundled WebKit runtime renders HTML,
  canvas and JavaScript with the sandbox enabled in an isolated Ubuntu container.
  The container's namespace capability is needed for nested sandbox testing.
- Debian 13 validation is blocked locally by the x64 emulator's unsupported
  syscall in Debian's bubblewrap. This is not a Debian compatibility pass.

## Native and device verification

- Windows run [38086067580](https://github.com/PapyrusReader/client/actions/runs/38086067580)
  at client commit `5a48d6f` passed installer lifecycle, Start menu presence,
  upgrade from installer version `0.0.0+1` to `0.0.0+2`, WebView2 rendering and
  the installed instrumented reader's EPUB/PDF, offline import, persisted resume
  and guest/account/server-profile isolation tests. Its uploaded JSON report
  records success. The test entrypoint uses production reader and storage code;
  it is not the production application's interactive entrypoint.
- Native Ubuntu launched the AppImage with a scoped AppArmor namespace profile.
  Its initial follow-up WebKit check exposed an executable cleanup race in the
  test harness; Debian and Linux reader validation remain pending the corrected run.
- A connected Android device reports `versionName=0.0.1`, `versionCode=1` and
  both installer and initiating package `com.android.vending`. This confirms
  the existing Play installation, not installation of the next release.
- Coordinated server preparation: 372 backend tests pass, including the additive
  goal-table migration, existing-library preservation and metadata comparison;
  two external provider tests are excluded. Ruff and Mypy pass. Server PR #15
  also passes GitHub CI. Production is still server `0.0.1`, migration
  `af0fea8d6317`; the next server must deploy before its client.

## Required before declaring delivery operational

- [x] Verify restricted Papyrus testing access and confirm API access.
- [ ] Run the new native Linux and Windows packaging workflows on the current
  source revision. Windows checks include installer lifecycle and WebView2
  HTML/canvas/JavaScript rendering; Linux checks include Debian without system
  WebKit. These workflows have been added but have not run remotely yet.
- [ ] Check fresh Windows installation with WebView2 absent, upgrade from a
  previous version, Start menu/icon, uninstall and preservation of a real library,
  settings and credentials. Reinstalling one package is not this upgrade test.
- [ ] Check actual packaged EPUB/PDF reading, offline imports, reader resume and
  guest/account/server-profile isolation on Windows and both Linux targets.
- [ ] Promote the completed changes through the normal development-to-master
  release process with the next properly incremented committed version.
- [ ] Verify deployed `/release.json`, entrypoint and client-side route against
  that release, and exercise a delivery retry without rebuilding.
- [ ] Install that exact release from Google Play internal testing on a device.
  An active internal track or successful API upload alone is not installation
  verification.

The existing release predates the new manifest and cannot be retroactively used
as a delivery retry. The currently deployed web app likewise has no release
metadata yet. Keep Apple, ARM64, public store launches and automatic desktop
updates deferred.
