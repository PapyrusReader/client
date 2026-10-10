# Install Papyrus

Download all packages from the matching GitHub release. `release-manifest.json`
records the version, build number, source commit and SHA-256 of each download.
Verify downloads with `sha256sum --check SHA256SUMS` after downloading all assets,
or compare the selected file's hash with its entry in `SHA256SUMS`.

## Android

Android releases are for Google Play **internal testing**. Join the tester list
and use its Play opt-in link. The AAB is a Play upload artifact, not a directly
installable APK. Public Play production distribution is not enabled.

## Web

Open https://app.papyrus-reader.com. Web releases deploy automatically after
GitHub publication. `/release.json` identifies the running release. Browser
storage, offline libraries and accounts are not cleared by deployment.

## Windows x64

Download `papyrus-vVERSION+BUILD-windows-x64-setup.exe` and run it as your normal
user. It installs under your user profile, adds a Start menu shortcut and can
upgrade an existing installation. Close Papyrus before upgrading.

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

Replace the AppImage to upgrade. The `.tar.gz` bundle remains available for manual
installation with the same system-library requirements as the `.deb`.

Ubuntu 24.04 and Debian 13 are the AppImage validation targets. Only releases whose
packaging checks and graphical reader smoke tests have passed on a target should
be described as verified there; an archive build alone is not compatibility proof.
