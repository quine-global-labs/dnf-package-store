# DNF Package Store

A lightweight Flutter desktop app for browsing and trying out packages on
DNF-based Linux distros (Fedora and friends), without committing to a
permanent install.

## Features

- Search or browse the full package catalog, scoped to a single repo/channel
  or across all enabled repos.
- Browse by category — AppStream app categories and comps groups, shown as
  tags on each package.
- Install packages **transiently** (`dnf install --transient`), so test
  installs disappear automatically on reboot instead of lingering.
- Launch installed apps directly, or uninstall them immediately.
- Settings page to uninstall PackageKit (and its AppStream catalog data) if
  you only wanted it for the richer category listings.

## Getting Started

This is a standard Flutter project targeting Linux desktop. With the Flutter
SDK on your `PATH`:

```sh
flutter run -d linux
```

## Package history

`pkg-history` (repo root) is a separate, standalone script — not part of the
Flutter app — that lists rpm-ostree deployments (the real revision history on
an image-based/bootc system like Aurora, as opposed to `dnf history`, which
doesn't apply here). It's plain Python 3 calling `rpm-ostree`, `journalctl`
and `getent`, all already on the host, so it needs no build step and no
toolbox:

```sh
./pkg-history
```

The app's "Package history" toolbar button just opens this script in a
terminal.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
