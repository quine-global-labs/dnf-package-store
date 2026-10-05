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

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
