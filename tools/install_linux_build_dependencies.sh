#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" == 'true' && -f /etc/apt/apt-mirrors.txt ]]; then
  # The hosted runner's Azure mirror can stall before falling back to Ubuntu.
  printf '%s\n' 'https://archive.ubuntu.com/ubuntu' | sudo tee /etc/apt/apt-mirrors.txt >/dev/null
fi

apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
sudo apt-get "${apt_options[@]}" update
sudo apt-get "${apt_options[@]}" install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libwebkit2gtk-4.1-dev libsecret-1-dev \
  liblzma-dev libstdc++-12-dev \
  python3 squashfs-tools dpkg-dev file imagemagick desktop-file-utils patchelf \
  bubblewrap xdg-dbus-proxy xvfb xauth dbus-x11 \
  libgdk-pixbuf2.0-bin librsvg2-common gstreamer1.0-plugins-base gstreamer1.0-plugins-good

pkg-config --print-errors --exists gtk+-3.0 webkit2gtk-4.1 libsecret-1
pkg-config --print-errors --atleast-version=0.18.4 libsecret-1
