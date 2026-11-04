# Built by quine-global/app-build (kind flutter) from Flutter's release bundle; not
# a from-source spec (no %prep/%build).
%global debug_package %{nil}
# The bundle's own libraries (libflutter_linux_gtk.so, plugins) are private,
# and the executable links them from its own lib/, so no automatic
# dependencies from the bundle: the Requires below are what it needs from the
# system (the image build checks every library resolves).
%global __provides_exclude_from ^%{_libexecdir}/%{name}/.*$
%global __requires_exclude_from ^%{_libexecdir}/%{name}/.*$

Name:           dnf-package-store
Version:        %{version_}
Release:        %{release_}%{?dist}
Summary:        Browse DNF packages and try them out with transient installs
License:        LicenseRef-Not-Specified
URL:            https://forge.quinefoundation.com/quine-global-labs/dnf-package-store
ExclusiveArch:  x86_64 aarch64

Requires:       gtk3
Requires:       polkit
Requires:       dnf5
Requires:       python3
Requires:       rpm-ostree

%description
A desktop app for browsing the package catalog of DNF-based systems and
installing packages transiently (dnf install --transient), so test installs
disappear on reboot. pkg-history lists the system's rpm-ostree deployments.

%install
mkdir -p %{buildroot}%{_libexecdir}/%{name} %{buildroot}%{_bindir}
cp -a %{bundle}/. %{buildroot}%{_libexecdir}/%{name}/
# Next to the executable, where the app looks for pkg-history (lib/main.dart).
install -m 0755 %{srcdir}/pkg-history %{srcdir}/pkg-apply %{buildroot}%{_libexecdir}/%{name}/
ln -s ../libexec/%{name}/dnf_package_store %{buildroot}%{_bindir}/%{name}
ln -s ../libexec/%{name}/pkg-history %{buildroot}%{_bindir}/pkg-history
mkdir -p %{buildroot}%{_datadir}/applications
cat > %{buildroot}%{_datadir}/applications/com.ironmagma.dnf_package_store.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DNF Package Store
Comment=Browse packages and try them out without keeping them
Exec=dnf-package-store
Icon=system-software-install
Categories=System;PackageManager;
StartupWMClass=com.ironmagma.dnf_package_store
DESKTOP
desktop-file-validate %{buildroot}%{_datadir}/applications/com.ironmagma.dnf_package_store.desktop

%files
%{_libexecdir}/%{name}
%{_bindir}/%{name}
%{_bindir}/pkg-history
%{_datadir}/applications/com.ironmagma.dnf_package_store.desktop
