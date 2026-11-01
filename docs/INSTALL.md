# Install Papyrus

Download all packages from the matching GitHub release. `release-manifest.json`
records the version, build number, source commit and SHA-256 of each download.
Verify downloads with `sha256sum --check SHA256SUMS` after downloading all assets,
or compare the selected file's hash with its entry in `SHA256SUMS`.

## Android

Download `papyrus-vVERSION+BUILD-android-universal.apk` for direct installation.
Open it on your Android device and allow installation from that browser or file
manager when prompted. Use About → App updates for subsequent releases. Android may ask you to allow
Papyrus to install updates. Updates retain your library and settings. Older
builds need one manual APK upgrade to acquire the updater.

Google Play internal testers can instead use the Play opt-in link. The AAB is
for Play publishing. Play-installed builds receive Play updates, including while
in internal testing. Enable auto-update in Play or use About → App updates.
Use the APK when installing a downloaded file.

Direct APKs use Papyrus's upload signing key. Google Play uses its app signing
key, so Android may reject switching between the two installation sources.
Stay with the same source for updates. Do not uninstall an existing app just to
switch sources without first exporting any local-only books and data.

## Web

Open https://app.papyrus-reader.com. Web releases deploy automatically after
GitHub publication. `/release.json` identifies the running release. Browser
storage, offline libraries and accounts are not cleared by deployment.

## Windows x64

Download `papyrus-vVERSION+BUILD-windows-x64-setup.exe` and run it as your normal
user. It installs under your user profile, adds a Start menu shortcut and can
upgrade an existing installation. For future releases, use About → App updates. Once downloaded, close Papyrus
normally to install the update and reopen the app. Older builds need one manual
upgrade to acquire the updater.
Setup offers an optional desktop shortcut, unchecked on a fresh installation.

The installer is unsigned: Windows may show an unknown-publisher/SmartScreen
warning. Verify the GitHub source and checksum before choosing to continue.
No paid signing service is configured.

The installer includes Visual C++ runtime DLLs and Microsoft's offline Evergreen
WebView2 Runtime installer. WebView2 is installed only when missing. Uninstalling
Papyrus preserves your library, credentials and settings; it does not remove a
shared WebView2 installation.

The ZIP remains available for manual installation. Extract the whole archive,
including `data` and all DLLs, before launching `papyrus.exe`. Install Microsoft's
Evergreen WebView2 Runtime separately if it is absent; the ZIP does not bundle its
installer. Do not run installed and portable copies concurrently against the same
user profile.

## Linux x64

The build baseline is Ubuntu 24.04. Compatibility on older distributions is not
claimed. Both packages preserve the existing Papyrus application identity and
user-data directories. Package removal does not delete your library.

### Ubuntu package

Install the `.deb` through your package manager, for example:

```sh
sudo apt install ./papyrus-vVERSION+BUILD-linux-x64.deb
```

APT resolves GTK, WebKitGTK, secret storage and other native dependencies. Launch
Papyrus from the application menu or run `papyrus`. Install a later package to
upgrade; remove it with `sudo apt remove papyrus`.

### AppImage

The AppImage includes GTK, WebKitGTK and its helper processes. It still needs a
working graphical desktop, graphics drivers, a Secret Service/keyring provider,
`bubblewrap`, `xdg-dbus-proxy` and permission to create unprivileged user namespaces.
The launcher uses a mount namespace for WebKit's compiled-in helper paths and
preserves WebKit's sandbox. It does not disable sandbox or host security policies.

```sh
chmod +x papyrus-vVERSION+BUILD-linux-x64.AppImage
./papyrus-vVERSION+BUILD-linux-x64.AppImage
```

If FUSE is unavailable, extract and run it:

```sh
./papyrus-vVERSION+BUILD-linux-x64.AppImage --appimage-extract
./squashfs-root/AppRun
```

Use About → App updates to download and verify a new AppImage. The image must
be writable. Close and reopen Papyrus to use the update. Older builds need one
manual replacement to acquire the updater. The `.tar.gz` bundle remains available for manual
installation with the same system-library requirements as the `.deb`.

Ubuntu 24.04 and Debian 13 are the AppImage validation targets. Only releases whose
packaging checks and graphical reader smoke tests have passed on a target should
be described as verified there; an archive build alone is not compatibility proof.

Ubuntu 24.04's default AppArmor policy can reject the AppImage with
`bwrap: setting up uid map: Permission denied`. Prefer the `.deb` on such systems.
An administrator can instead grant user namespaces through an application-specific
AppArmor profile. Do not disable AppArmor or the global user-namespace restriction.
For an AppImage installed at a fixed path, use Ubuntu's documented `userns` profile
pattern with that exact path; extracted launches must enter the same named profile
with `aa-exec -p PROFILE -- /path/to/squashfs-root/AppRun`. Native CI validates this
explicit namespace prerequisite, rather than claiming compatibility with Ubuntu's
unmodified default policy.

## Subscribe to Linux package updates

This is available after the first release containing `InRelease` and
`papyrus-archive-keyring.gpg`. Download the key from that release and compare its
fingerprint with the maintainer's published `APT_SIGNING_FINGERPRINT` before
installing it. Then run:

```sh
sudo install -m 644 papyrus-archive-keyring.gpg /usr/share/keyrings/papyrus-archive-keyring.gpg
printf '%s\n' 'deb [arch=amd64 signed-by=/usr/share/keyrings/papyrus-archive-keyring.gpg] https://github.com/PapyrusReader/client/releases/latest/download/ ./' | sudo tee /etc/apt/sources.list.d/papyrus.list
sudo apt update
sudo apt install papyrus
```

Future versions appear in your system's package updater. Automatic installation
depends on your system's settings for third-party repositories. If a new release
appears between refreshing the index and installing, run `sudo apt update` again.
Do not use `trusted=yes` or disable signature verification.
