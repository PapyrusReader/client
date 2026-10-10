#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
tag="${1:?Expected release tag}"
if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]]; then
  echo 'Invalid release tag' >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
number="${BASH_REMATCH[2]}"
bundle="$PWD/build/linux/x64/release/bundle"
dist="$PWD/dist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$dist"
test -x "$bundle/papyrus"
base="papyrus-${tag}-linux-x64"
tar -czf "$dist/$base.tar.gz" -C "$bundle" .

package="$work/deb"
mkdir -p "$package/opt/papyrus" "$package/usr/bin" "$package/DEBIAN" \
  "$package/usr/share/applications" "$package/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$package/opt/papyrus/"
ln -s /opt/papyrus/papyrus "$package/usr/bin/papyrus"
cp ../packaging/linux/com.papyrus.papyrus.desktop "$package/usr/share/applications/"
convert assets/images/logo.png -resize 256x256 -background none -gravity center -extent 256x256 "$package/usr/share/icons/hicolor/256x256/apps/com.papyrus.papyrus.png"
# Resolve shared-library package dependencies from the actual binary bundle.
mkdir -p "$work/shlibs/debian"
printf 'Source: papyrus\nSection: misc\nPriority: optional\nMaintainer: PapyrusReader <support@papyrus-reader.com>\nStandards-Version: 4.6.2\n\nPackage: papyrus\nArchitecture: amd64\nDescription: Offline book library and reader\n' > "$work/shlibs/debian/control"
executables=()
while IFS= read -r -d '' library; do
  if file "$library" | grep -q ELF; then executables+=(-e "$library"); fi
done < <(find "$package/opt/papyrus" -type f -print0)
dependencies=$(cd "$work/shlibs" && dpkg-shlibdeps --ignore-missing-info -O -l"$package/opt/papyrus/lib" "${executables[@]}")
dependencies="${dependencies#shlibs:Depends=}"
cat > "$package/DEBIAN/control" <<CONTROL
Package: papyrus
Version: ${version}-${number}
Architecture: amd64
Maintainer: PapyrusReader <support@papyrus-reader.com>
Section: utils
Priority: optional
Depends: ${dependencies}, bubblewrap, xdg-dbus-proxy
Description: Offline book library and reader
Homepage: https://papyrus-reader.com
CONTROL
chmod -R go-w "$package"
dpkg-deb --root-owner-group --build "$package" "$dist/$base.deb"

fetch() {
  curl --fail --location --retry 3 "$1" --output "$work/$2"
  printf '%s  %s\n' "$3" "$work/$2" | sha256sum --check
  chmod +x "$work/$2"
}
fetch https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage linuxdeploy.AppImage c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
fetch https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh linuxdeploy-plugin-gtk.sh b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171
fetch https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage appimagetool.AppImage ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
fetch https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64 runtime-x86_64 2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
python3 ../tools/extract_appimage.py "$work/linuxdeploy.AppImage" "$work/linuxdeploy-tool"
python3 ../tools/extract_appimage.py "$work/appimagetool.AppImage" "$work/appimagetool-tool"
appdir="$work/AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/lib" "$appdir/usr/libexec/gstreamer-1.0" "$appdir/etc"
cp -aL /etc/fonts "$appdir/etc/"
cp -a "$bundle/." "$appdir/usr/bin/"
cp -a /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1 "$appdir/usr/lib/"
cp -a /usr/lib/x86_64-linux-gnu/gio "$appdir/usr/lib/"
cp -a /usr/lib/x86_64-linux-gnu/gstreamer-1.0 "$appdir/usr/lib/"
cp /usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner "$appdir/usr/libexec/gstreamer-1.0/"
export PATH="$work:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=3
libraries=()
while IFS= read -r -d '' library; do
  if file "$library" | grep -q ELF; then libraries+=(--library "$library"); fi
done < <(find "$appdir" -type f ! -name papyrus -print0)
LD_LIBRARY_PATH="$appdir/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
"$work/linuxdeploy-tool/AppRun" --appdir "$appdir" --executable "$appdir/usr/bin/papyrus" \
  "${libraries[@]}" --plugin gtk \
  --desktop-file ../packaging/linux/com.papyrus.papyrus.desktop \
  --icon-file "$package/usr/share/icons/hicolor/256x256/apps/com.papyrus.papyrus.png"
python3 ../tools/complete_appimage_libraries.py "$appdir"
# Include upstream copyright and redistribution notices for bundled dependencies.
mkdir -p "$appdir/usr/share/doc/build-system"
cp -a /usr/share/doc/. "$appdir/usr/share/doc/build-system/"
rm "$appdir/AppRun"
cp ../packaging/linux/AppRun "$appdir/AppRun"
chmod +x "$appdir/AppRun"
ARCH=x86_64 "$work/appimagetool-tool/AppRun" --runtime-file "$work/runtime-x86_64" "$appdir" "$dist/$base.AppImage"
