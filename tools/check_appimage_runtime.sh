#!/usr/bin/env bash
set -euo pipefail
image="$(realpath "${1:?Expected AppImage}")"
smoke="$(realpath "${2:?Expected compiled WebKit smoke helper}")"
namespace=()
if [[ -n "${PAPYRUS_APPARMOR_PROFILE:-}" ]]; then
  namespace=(aa-exec -p "$PAPYRUS_APPARMOR_PROFILE" --)
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(cd "$work" && "$image" --appimage-extract >/dev/null)
test -x "$work/squashfs-root/usr/lib/webkit2gtk-4.1/WebKitWebProcess"
test -x "$work/squashfs-root/usr/lib/webkit2gtk-4.1/WebKitNetworkProcess"
set +e
timeout 20s xvfb-run -a dbus-run-session -- "${namespace[@]}" "$work/squashfs-root/AppRun" > "$work/launch.log" 2>&1
result=$?
set -e
cat "$work/launch.log"
if [[ "$result" != 124 ]]; then
  echo "AppImage exited during launch check ($result)" >&2
  exit 1
fi
if grep -Ei 'error while loading shared libraries|symbol lookup error|Failed to load dynamic library' "$work/launch.log"; then
  exit 1
fi
# Replace only the disposable extracted executable to exercise the packaged
# WebKit runtime. The release AppImage is never changed by this test.
cp "$smoke" "$work/squashfs-root/usr/bin/papyrus"
timeout 45s xvfb-run -a dbus-run-session -- "${namespace[@]}" "$work/squashfs-root/AppRun"
