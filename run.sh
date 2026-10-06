#!/usr/bin/env bash
# Builds and runs the DNF Package Store Linux desktop app.
#
# The host OS is immutable (Fedora Aurora/Kinoite), so the native build
# toolchain (cmake, ninja, gtk3 headers) that `flutter build linux` needs
# lives in a toolbox instead of on the host. This script creates a default
# toolbox if none exists, installs those packages into it once, then builds
# and runs through it. The toolbox shares $HOME with the host, so the
# Flutter SDK and this project are visible from inside it without copying
# anything.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

FLUTTER=/var/home/ironmagma/Code/.flutter-sdk/bin/flutter

if ! toolbox list -c 2>/dev/null | tail -n +2 | grep -q .; then
  echo "No toolbox found — creating the default one..."
  toolbox create -y
fi

if ! toolbox run rpm -q cmake ninja-build gtk3-devel >/dev/null 2>&1; then
  echo "Installing Linux build dependencies into the toolbox..."
  toolbox run sudo dnf install -y cmake ninja-build gtk3-devel
fi

echo "Building..."
toolbox run "$FLUTTER" build linux --debug

BUNDLE="build/linux/x64/debug/bundle"
echo "Running $BUNDLE/dnf_package_store ${*}"
exec toolbox run "$BUNDLE/dnf_package_store" "$@"
