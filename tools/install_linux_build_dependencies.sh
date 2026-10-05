#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libwebkit2gtk-4.1-dev libsecret-1-dev \
  liblzma-dev libstdc++-12-dev

pkg-config --print-errors --exists gtk+-3.0 webkit2gtk-4.1 libsecret-1
pkg-config --print-errors --atleast-version=0.18.4 libsecret-1
