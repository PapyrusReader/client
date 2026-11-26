# Update flow testing

Test each distribution separately: Android Play, Android direct APK, Windows
installer, Windows ZIP, Linux AppImage, Linux Debian/APT, Linux archive, and web.
The AAB is a Play publishing artifact, not a separate installation channel.
macOS and iOS are not currently published client builds.

## Automated checks

From the workspace root:

```sh
tools/papyrus test client -- test/updates
tools/papyrus check client
```

From `client/app`, run the browser-specific regression:

```sh
../../tools/flutter test --platform chrome test/updates/update_web_test.dart
```

For the real process boundary, compile the harmless Setup fixture and run the
Windows launcher tests. Use `.exe` for the output name on Windows and set
`PAPYRUS_TEST_INSTALLER` to its absolute path:

```sh
../../tools/dart compile exe test/fixtures/update_installer.dart -o build/update-installer-fixture
PAPYRUS_TEST_INSTALLER="$PWD/build/update-installer-fixture" ../../tools/flutter test test/updates/update_windows_test.dart
```

The Windows packaging workflow runs this fixture natively. It checks paths with
spaces, successful completion, cancellation, launch failure, and Setup errors.
The fixture never replaces an installation. Package smoke tests separately run
Inno Setup and validate the reader and its persisted library.

## Inspect the update screens

On an Android emulator or connected test device:

```sh
../../tools/flutter drive --driver=test_driver/app_updates_driver.dart --target=integration_test/app_updates_test.dart --flavor direct -d DEVICE_ID
```

Screenshots are saved in `client/app/build/update-screenshots`. The test covers
light, dark, enlarged text, e-ink, check errors/retry, and download progress. Release metadata and installer results are simulated in
this UI test; it does not prove an operating-system upgrade succeeded.

Check the actual Android bridge in both flavors:

```sh
../../tools/flutter test integration_test/update_platform_test.dart --flavor direct -d DEVICE_ID
../../tools/flutter test integration_test/update_platform_test.dart --flavor play --dart-define=PAPYRUS_TEST_UPDATE_CHANNEL=play -d DEVICE_ID
```

Use a disposable emulator: these commands install debug builds with the same
application ID. Do not replace a user's signed release with a debug build.

## Update acceptance matrix

Use an older build with the revised updater and a newer, same-channel release.
Seed an offline book, reading position, annotation, and setting before updating.
After reopening, verify the installed build increased and those items survived.

| Distribution | Installation check | Cancellation and recovery |
| --- | --- | --- |
| Android direct APK | Allow Papyrus to install packages, return, tap Update, and complete Android's package installer. | Deny permission and cancel installation separately. Update remains available; retry works. Wrong signatures and package IDs are rejected. |
| Android Play | Install through the internal test track with a tester account eligible for a higher version code. Complete the immediate Play update. | Cancel, return, recheck eligibility, and retry. No GitHub APK is offered. A sideloaded Play-flavor debug APK cannot prove Play delivery. |
| Windows installer | Tap Update; verify Windows Setup appears. Follow Setup, close Papyrus when requested, finish, and reopen. | Cancel Setup, simulate a failed download, and retry. Starting Setup must not be reported as successful installation. Also test a user/install path containing spaces. |
| Windows ZIP | Open Downloads from the update dialog and replace the complete extracted bundle while Papyrus is closed. | No automatic installer is launched for a portable copy. |
| Linux AppImage | Update a writable original AppImage, close it, and reopen that same path. | A read-only destination, symlink, interrupted download, or bad hash must preserve the working image. |
| Linux Debian/APT | Update using the system package manager or configured Papyrus repository. | Papyrus offers repository guidance and never launches a downloaded executable. |
| Linux archive | Open Downloads and replace the complete extracted bundle while closed. | Papyrus offers manual instructions. |
| Web | Deploy a newer web release while the old build is cached. Open View update → Reload and verify the new build and existing offline library after reload. | With another Papyrus tab open, Reload should explain how to retry. Close the other tab and retry. An active reader stays open until the user chooses to reload. |

For all channels, the update notice and its actions occupy one row.
View update opens a modal over the current screen without hiding the notice.
The same backdrop must dim the banner and the rest of the screen, and prevent
interaction with banner actions while any root modal is open.
Dismiss, Escape, Back, and clicking outside close it and hide the notice for the
session. On mobile, close the modal with its header X. The banner also has a
Dismiss action (an X on mobile). Verify that the notice returns
after an app restart, including offline startup with a cached release.
Selecting Skip this version leaves an existing banner in place until dismissal
and suppresses that release across restarts, while a newer release is still offered.
A manual check reports its result in the dialog without creating a new banner.
Opening or closing the dialog while an automatic check is in flight must not
allow its late result to create a new banner. Manual checks in Settings must remain available
for a skipped release. Reading temporarily hides the notice without dismissing
it, and installing the offered build clears it. Turning off automatic checks
must not delete a previously found update. A staged AppImage or completed
Windows Setup keeps restart guidance accessible in the modal. Starting an update
hides Skip this version; cancellation or failure makes it available again.
Verify that the app stays responsive during download, checksum verification,
and the wait for Windows Setup to appear.

When repeating an upgrade test, install the older build without clearing app
preferences. With automatic checks enabled, changing the installed build must
trigger a fresh check even if the previous build checked within the last day.
Every app launch must check again, including when the same installed build
checked recently. The daily interval only throttles checks during an existing
session and on resume. Disabled automatic checks must still be respected.

An existing build with the old Windows updater needs one manual installation of
the fixed release before this revised flow can be exercised. Do not publish a
release or change production metadata just to manufacture a test update.

Record the OS, distribution, old/new build numbers, actual device or VM, results,
and logs outside published documentation. Keep simulated UI evidence separate
from native installation, store eligibility, and production delivery evidence.
