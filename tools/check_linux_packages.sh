#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
tag="${1:?Expected release tag}"
base="papyrus-${tag}-linux-x64"
dpkg-deb --info "dist/$base.deb"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
dpkg-deb --extract "dist/$base.deb" "$work/deb"
test -x "$work/deb/opt/papyrus/papyrus"
desktop-file-validate "$work/deb/usr/share/applications/com.papyrus.papyrus.desktop"
read -r -a webkit_flags <<< "$(pkg-config --cflags --libs webkit2gtk-4.1)"
cc ../packaging/linux/webkit_smoke.c -o "$work/webkit-smoke" "${webkit_flags[@]}"
bash ../tools/check_appimage_runtime.sh "dist/$base.AppImage" "$work/webkit-smoke"
# The Debian container deliberately has no system WebKitGTK installation.
# Extra namespace capability is confined to this disposable test container;
# WebKit's sandbox stays enabled inside it.
docker run --rm --cap-add SYS_ADMIN --security-opt seccomp=unconfined \
  --security-opt "apparmor=${PAPYRUS_APPARMOR_PROFILE:-unconfined}" \
  -v "$PWD/dist:/packages:ro" -v "$work/webkit-smoke:/webkit-smoke:ro" \
  -v "$PWD/../tools/check_appimage_runtime.sh:/check-runtime.sh:ro" \
  -e "PAPYRUS_TEST_IMAGE=/packages/$base.AppImage" debian:13-slim bash -ec '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap xdg-dbus-proxy \
      xvfb xauth dbus-x11 libgl1 libegl1 libgles2 libgl1-mesa-dri fonts-dejavu-core libnss3
    useradd -m tester
    runuser -u tester -- bash /check-runtime.sh "$PAPYRUS_TEST_IMAGE" /webkit-smoke
  '
# A package-manager install and removal must leave user-owned data intact.
mkdir -p "$HOME/.local/share/com.papyrus.papyrus"
sentinel="$HOME/.local/share/com.papyrus.papyrus/packaging-preserve-test"
test ! -e "$sentinel"
printf 'preserve-user-data\n' > "$sentinel"
sudo apt-get install -y "$PWD/dist/$base.deb"
test -x /opt/papyrus/papyrus
sudo apt-get install --reinstall -y "$PWD/dist/$base.deb"
sudo apt-get remove -y papyrus
test "$(cat "$sentinel")" = 'preserve-user-data'
rm "$sentinel"
