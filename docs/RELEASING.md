# Android internal testing releases

Android identity is `com.papyrus.reader`; the first uploaded bundle establishes it
in Play Console. Keep this identity for all subsequent uploads.
The app name is Papyrus. The pinned Flutter 3.41.2 toolchain targets Android API 36.

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
`v1.0.0+1`. Version changes build Android, web, Linux and Windows as before; the
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
4. Dispatch Release on `master` for the initial `1.0.0+1`, download the
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

The workflow prepares builds; it does **not** upload to or publish on Play. The
first app upload/setup is manual. A later Play API upload workflow can use a
restricted service account after the app has been initialized.

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
