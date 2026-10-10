#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
tag="${1:?Expected instrumented package tag}"
base="papyrus-${tag}-linux-x64"
reports="$PWD/build/package-smoke-results"
image="$PWD/dist/$base.AppImage"
mkdir -p "$reports"
namespace=()
if [[ -n "${PAPYRUS_APPARMOR_PROFILE:-}" ]]; then
  namespace=(aa-exec -p "$PAPYRUS_APPARMOR_PROFILE" --)
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Separate test entrypoint with production import, persistence and reader code.
# Published artifacts are never replaced with this instrumented application.
(cd "$work" && "$image" --appimage-extract >/dev/null)
python3 ../tools/run_packaged_smoke.py --report "$reports/ubuntu-appimage.json" -- \
  xvfb-run -a dbus-run-session -- "${namespace[@]}" "$work/squashfs-root/AppRun"
sudo apt-get install -y "$PWD/dist/$base.deb"
python3 ../tools/run_packaged_smoke.py --report "$reports/ubuntu-deb.json" -- \
  xvfb-run -a dbus-run-session -- /opt/papyrus/papyrus
sudo apt-get remove -y papyrus
# Allow nested WebKit namespaces only in this disposable test container.
# No system WebKit or GTK is installed; the AppImage must supply them.
chmod 777 "$reports"
docker run --rm --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  -v "$image:/papyrus.AppImage:ro" -v "$reports:/reports" \
  -v "$PWD/../tools/run_packaged_smoke.py:/run-smoke.py:ro" debian:13-slim bash -ec '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap xdg-dbus-proxy \
      xvfb xauth dbus-x11 libgl1 libegl1 libgles2 libgl1-mesa-dri fonts-dejavu-core libnss3 python3
    useradd -m tester
    cd /tmp
    runuser -u tester -- /papyrus.AppImage --appimage-extract >/dev/null
    runuser -u tester -- python3 /run-smoke.py --report /reports/debian-appimage.json -- \
      xvfb-run -a dbus-run-session -- /tmp/squashfs-root/AppRun
  '
chmod 755 "$reports"
