# Client releases and delivery

Android identity is `com.papyrus.reader`; the first uploaded bundle establishes it
in Play Console. Keep this identity for all subsequent uploads.
The app name is Papyrus. The pinned Flutter 3.41.2 toolchain targets Android API 36.

## Branch workflow

Feature and fix PRs target the default `development` branch. Merge them without
bumping the version. CI checks PRs and integration pushes; `development` does not
build or publish releases.

When ready to release the accumulated changes, prepare the coordinated version
bump in a PR to `development`, then open `development` → `master`. Use **Create a
merge commit** for this promotion and bring `master` back into `development`
afterwards. The workspace release runbook describes the server/client merge
order. Keep both branches; do not squash release promotions.

## Versions and triggers

`app/pubspec.yaml` owns `version: MAJOR.MINOR.PATCH+BUILD`. The semantic portion
matches the server release; `BUILD` is a positive, globally increasing Android
version code. Do not derive it from a workflow run number. Every new Play upload
must use a higher code, including rebuilds of the same semantic release.

The Release workflow considers changes to this file on `master`, then compares
its version value with the previous push commit. Dependency-only edits skip all
release builds. Normal PR CI continues independently. Manual dispatch on `master`
is available for the first build or a retry of an unreleased commit. Tags are
created after builds, not used as a second build trigger. A released tag cannot
be reused for a different commit. Client tags include the build number, e.g.
`v0.0.1+1`. Version changes build Android, web, Linux and Windows as before; the
Android artifact is now a signed AAB, which Google Play turns into device APKs.
The Android artifact is available even if an unrelated desktop job fails.

Use the workspace `tools/release.py bump` command to coordinate manifest changes
with the server rather than editing each version separately. See the workspace
release runbook for merge order.

## Configure GitHub before the first build

The client GitHub **environment named `release`** is restricted to `master`.
Its public endpoint variables use the registered `papyrus-reader.com` domain:

| Variable | Release value |
| --- | --- |
| `PAPYRUS_API_BASE_URL` | `https://api.papyrus-reader.com` |
| `POWERSYNC_SERVICE_URL` | `https://sync.papyrus-reader.com` |

Use origins without `/v1`: the client adds the API prefix. HTTP, private addresses,
localhost and placeholder endpoints are rejected. These addresses are public
configuration, not secrets. Existing development defaults remain available in
local debug builds. Changing endpoints requires a new Android build number.

Generate an **upload key**, not a debug key, on your own machine and store a
backup securely. For example (keytool prompts for the passwords):

```sh
keytool -genkeypair -v -keystore upload.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Put these secrets in the same GitHub environment:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the upload keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `upload`, or the alias you chose |
| `ANDROID_KEY_PASSWORD` | Key password |

The workflow restores the file in runner temporary storage, builds the AAB,
checks 64-bit native ELF alignment for 16 KB page support, uploads the artifact,
and removes the temporary key. Never commit a keystore or passwords.

Local release builds use the same four environment variables (replace
`ANDROID_KEYSTORE_BASE64` with `ANDROID_KEYSTORE_PATH`, an absolute local path),
or an ignored `app/android/key.properties`:

```properties
storeFile=/absolute/path/upload.jks
storePassword=your-password
keyAlias=upload
keyPassword=your-password
```

Debug builds keep debug signing. Release builds without an upload key fail with
an actionable message; they cannot silently use the debug certificate.

## First Google Play upload

1. Create Papyrus in Play Console with the appropriate account/developer details.
   The first uploaded bundle uses `com.papyrus.reader`. Choose **internal testing**
   for the first device test.
2. Enable Play App Signing. Google holds the app signing key; GitHub uses your
   upload key. Keep the same upload key for later releases.
3. Configure the public API, PowerSync, SMTP and Google OAuth settings using the
   server deployment runbook. Check the endpoints from outside your local network.
4. Merge the initial `0.0.1+1` version change (or dispatch Release on `master`), download the
   `android-release` artifact, and upload `app-release.aab` to internal testing.
   The local validation bundle uses a temporary certificate and placeholder
   URLs and must **never** be submitted to Play.
5. Add testers and share Play's opt-in link. Install through Play on real devices
   and test offline importing/reading, sign-in/callback, profile switching,
   media upload/download, sync/reconnect and reader resume.
6. Check Play's native-library/page-size diagnostics. ELF alignment checks do not
   replace APK packaging or actual Android 16 KB emulator/device tests. Use
   `bundletool dump config --bundle=app-release.aab` to verify
   `PAGE_ALIGNMENT_16K`, and test an APK generated from the bundle.

After GitHub publication, the delivery workflow automatically sends the signed
bundle to Play internal testing and deploys the web app in independent jobs.
The first app upload/setup remains manual. Configure the restricted Play service
account described below before the next release. Delivery failures do not remove
published downloads.

## Before closed testing or production

Complete Play's app content and store forms: privacy policy URL, Data safety,
content rating, target audience, app access instructions/test login, screenshots,
512 px store icon and feature graphic. Declare the actual server/account/book
file behavior rather than claiming that all data stays on-device.

Papyrus currently supports account creation but has no account-deletion flow.
Google Play requires account deletion within the app and an external deletion
request URL for applicable distribution tracks. Implement and validate deletion
of the user's account and associated data before broader distribution. Publishing
an invented privacy policy or marking this requirement complete is not part of
build preparation. Check the Console requirements for your developer account;
new personal accounts may require closed testing before production access.

Official references:
- [Flutter Android release and signing](https://docs.flutter.dev/deployment/android)
- [Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Android 16 KB page support and testing](https://developer.android.com/guide/practices/page-sizes)
- [Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)

## Distribution artifacts

Every download includes `vMAJOR.MINOR.PATCH+BUILD` in its filename. Desktop
artifacts also include `x64`; the Android AAB is `android-universal` and web is
architecture independent. GitHub releases contain the AAB, web ZIP, Linux tarball,
`.deb`, AppImage, Windows ZIP and installer, plus `INSTALL.md`,
`release-manifest.json` and `SHA256SUMS`. See [installation instructions](INSTALL.md).

Linux uses Ubuntu 24.04 as its build baseline. The AppImage packages WebKit helper
processes and GTK resources; it requires host bubblewrap/xdg-dbus-proxy and user
namespaces to preserve WebKit's sandbox. Do not disable sandboxing to make a test
pass. Validate the installed `.deb` on Ubuntu 24.04 and AppImage on Ubuntu 24.04
and Debian 13. Run EPUB/PDF rendering, offline import, resume and profile switching
on real graphical sessions before advertising compatibility. Headless startup
checks alone do not establish reader functionality.

Windows uses an unsigned, per-user Inno Setup installer. Visual C++ runtimes are
included, and Microsoft's Authenticode-verified offline WebView2 installer runs
only when needed. Test a clean Windows x64 machine both with and without WebView2,
then upgrade and uninstall while retaining a real library. No trusted signing
service, Microsoft Store submission or automatic desktop updater is configured.

Packaging PR checks need no production credentials. The release packaging jobs
use the production endpoints, preserve the signed Android bundle alignment
checks, and only publish after every required build/package job succeeds.

## Play service account

See [delivery rollout evidence](DELIVERY_ROLLOUT.md) for completed setup and the
remaining operational acceptance checks.

1. In the existing Google Cloud project, enable the Google Play Android Developer
   API and create a service account dedicated to this client.
2. Invite that service account in Play Console with access to **only**
   `com.papyrus.reader`, app information visibility and testing-track release
   permissions. Do not grant production, financial or account-administration
   permissions. Initialize the app, upload the first AAB manually, and complete
   the internal-testing setup and tester list.
3. Store its JSON key as `PLAY_SERVICE_ACCOUNT_JSON` in the client GitHub
   `release` environment. Keep the key out of Git, logs and artifacts.
   The API preflight authenticates directly using Google's pinned Python auth
   library; it needs no Cloud project role or IAM impersonation permission.
4. Delivery compares Play's version code and bundle SHA-256 before upload. A
   matching completed internal release is a no-op; a matching uploaded bundle
   can be promoted without uploading again. Different content at the same code
   or a newer existing code fails. The target is always `internal`, status
   `completed`. Draft-app restrictions fail visibly and must be resolved in
   Console rather than silently changing the requested delivery status.

## Web deployment account

The host serves `/srv/apps/papyrus/deploy/web/current` through its existing Caddy
container. Keep the parent `web` directory mounted; mounting the symlink target
would prevent activation of subsequent releases.

1. Run the server's `deploy/migrate_web_layout.py` against the existing flat web
   directory. It copies the deployed files into an initial release, creates
   `current`, and preserves the original flat files. Install the updated Caddy
   configuration and reload **only** the web Caddy process. Check `/` and `/login`.
2. Install `tools/install_web.py` as root-owned
   `/usr/local/lib/papyrus-web/install_web.py` on the host. Give a dedicated
   `papyrus-web-deploy` user write access only to the web artifact directory;
   do not add it to Docker or sudo groups.
3. Generate a dedicated SSH key. Its root-owned authorized-keys entry must use
   `restrict,command="/usr/bin/python3 /usr/local/lib/papyrus-web/install_web.py --root /srv/apps/papyrus/deploy/web"`.
   This command accepts only `deploy REVISION SHA256 TAG` and an archive on stdin.
   Do not permit arbitrary SSH commands or reuse the website/API deployment key.
4. Add `WEB_SSH_HOST`, `WEB_SSH_USER` and verified `WEB_SSH_KNOWN_HOSTS` as variables
   in the GitHub `release` environment; add `WEB_SSH_PRIVATE_KEY` as a secret.

The receiver validates the ZIP checksum, entry paths, required files and embedded
release identity, then switches `current` atomically under a file lock. Public
`/release.json`, `/`, `/login` and `/flutter_bootstrap.js` must match the artifact.
A failed verification restores the previous target. Old directories are retained;
there is no automatic data or artifact deletion. Caddy revalidates web content.
If Cloudflare fronts the app, configure an app-host-only cache rule for
`http.host eq "app.papyrus-reader.com"`: bypass the edge cache and set Browser TTL
to **Respect origin TTL**. The default browser TTL can otherwise replace Caddy's
`no-cache` header with a four-hour lifetime for JavaScript. The public deployment
probe checks revalidation headers and exact bytes for metadata, both entrypoint
routes, the Flutter bootstrap and `main.dart.js`; failure rolls activation back.
The deployment user cannot restart or change the API, sync service or database.

Delivery rejects a lower build number than the active web release; an equal
build number must have identical metadata and archive checksum. Retrying an old
tag cannot silently downgrade production.

For an operator rollback, atomically replace `current` with the relative target
recorded by `previous` while holding `.deployment.lock`, then verify the app. The
`previous` link is retained across an identical successful delivery retry.

## Delivery retries and release immutability

Use **Deliver published release** → **Run workflow** on `master`, enter the exact
published tag, and choose `web`, `play` or `all`. This downloads existing assets,
resolves the tag to its commit, and verifies the release manifest and checksums.
It never rebuilds the application. Historic releases without a manifest cannot
be delivered by this workflow; prepare a new versioned release instead.

Do not rerun the build workflow to retry delivery: rebuilt bytes may differ.
Existing published assets are never overwritten. A draft interrupted during
publication must be inspected and completed with its original artifacts; if
those are unavailable, discard the draft and use a new build number. Tags cannot
be reassigned. Release summaries distinguish builds, GitHub publication, web
verification and Play delivery. Missing credentials are errors, not successful
skips. Actual tester installation is a separate check from API acceptance.
