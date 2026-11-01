# App update delivery

## Plan and scope

1. Add a shared update controller and About → App updates. Release builds check
   at startup and at most once daily while running, with an opt-out. Checks never
   block library startup. Notices stay hidden while reading and can be dismissed.
2. Keep Android updates in their distribution channel. Play builds ask Google
   Play for account-eligible updates, including internal testing releases. A
   separate `direct` flavor installs verified APKs using Android's confirmation
   flow. Only that flavor declares installation permission and a narrow file
   provider. Both retain `com.papyrus.reader` and existing signing identities.
3. Installed Windows builds download and verify the Inno installer, then wait for
   normal app shutdown. A helper rechecks the checksum, upgrades the existing
   directory without forcing shutdown or reboot, and relaunches Papyrus. Portable
   ZIP installations retain manual delivery. Installer failures leave a log and
   the verified installer in the temporary update directory for recovery.
4. AppImage builds download and verify the full replacement, stage it beside the
   existing file and rename atomically. The running process keeps its old image
   until the user closes it. This uses the same manifest updater as Windows rather
   than introducing a separate delta-update dependency. Extracted and tarball
   builds retain manual delivery.
5. Publish an optional signed flat APT repository as GitHub release assets. Once
   configured, `.deb` users subscribe once and use their normal software updater.
6. Web builds compare their compiled build number with the deployed `release.json`
   and reload only when requested. Existing centrally deployed delivery is retained.

## Trust and release contract

The native manifest URL is fixed to the public PapyrusReader/client GitHub
repository over HTTPS. It accepts only increasing build numbers, expected asset
names, and SHA-256 hashes. Download URLs are constructed from the validated tag
and platform, never taken from arbitrary feed URLs. Partial and corrupt downloads
are discarded. GitHub release publication permissions are the trust boundary.
Checksums do not provide an independent signature if the release account itself
is compromised. Windows Authenticode signing remains a separate future setup.
Android additionally verifies the installed package identity and signing
certificate before handing the APK to the OS installer.

The Play AAB has no sideload-install permission. Build it with `--flavor play`
(the default). Build the direct APK from the `--flavor direct` AAB. The release
workflow produces both from the same revision. Never redirect Play builds to the
APK feed or switch keys to make an update install.

The update controller and preferences are app-wide. Update packages use temporary
storage. No updater migrates, clears, or replaces library databases, profiles,
books, credentials, or reading positions. Normal database migrations still apply
when the new app starts.

## APT activation

Before the first APT-enabled release, create a dedicated OpenPGP signing key,
back it up securely, and configure the client repository's `release` environment:

- Secret `APT_SIGNING_KEY`: ASCII-armored private signing key usable by batch GPG.
- Variable `APT_SIGNING_FINGERPRINT`: the complete 40-character fingerprint.
- Variable `APT_UPDATES_ENABLED`: `true`.

Keep that signing identity stable across releases. Set a rotation procedure before
expiry. Once enabled, keep APT enabled for all subsequent releases, because the
subscription follows GitHub's latest published release. Missing signing material
fails publication when enabled. Disabled APT leaves existing release delivery
working but does not provide a repository. No secret is stored in this repository.

The release job publishes `Packages`, `Packages.gz`, `Release`, `Release.gpg`, `InRelease`,
and `papyrus-archive-keyring.gpg` together with the `.deb`. The common release
manifest and checksum index cover them too. APT verifies the signed index and
package hash independently. If a release changes between `apt update` and
installation, repeat `apt update` to refresh the flat repository snapshot.

## Acceptance before enabling distribution

- Run the controller, downloader, widget, release-tool and package checks.
- Build web and both Android flavors. Inspect merged manifests to verify only
  `direct` requests package installation permission.
- Play: install build N through internal testing, publish N+1 to the same track,
  check and accept the update. Also cancel it and confirm offline reading works.
- APK: install N, decline then allow installation permission, update to N+1,
  cancel and retry. Confirm Android rejects a package signed with another key.
- Windows x64: install N, download N+1 through the app, keep reading, close
  normally and verify upgrade/relaunch and retained local books/positions. Test
  paths with spaces, a failed installer, and portable ZIP fallback.
- Linux: update a writable AppImage while running, restart and verify version and
  retained data. Test read-only paths and extracted-image fallback. Install the
  APT signing key once, upgrade a real `.deb` through the repository and verify
  a tampered index/package is rejected.
- Web: leave N open, deploy N+1, check/reload outside the reader and verify local
  data survives. Test an offline check and a narrow e-ink layout.

Older installed desktop/APK builds need one manual upgrade to acquire this code.
Play-installed testers already receive updates through Play. Source changes do
not activate a release, provision APT signing material, or establish native-device
acceptance on their own.
