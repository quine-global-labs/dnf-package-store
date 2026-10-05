import 'dart:io';

/// Standard top-level freedesktop/AppStream categories. Used both as the
/// button set and as the keys enumerated via `appstreamcli list-categories`.
const List<String> appstreamCategories = [
  'AudioVideo',
  'Development',
  'Education',
  'Game',
  'Graphics',
  'Network',
  'Office',
  'Science',
  'Settings',
  'System',
  'Utility',
];

class CategoryIndex {
  /// package name -> every AppStream category it appears under (source #2).
  final Map<String, Set<String>> appstream;

  /// package name -> every comps group it belongs to (source #1, shown
  /// alongside AppStream categories rather than only as a fallback for tags).
  final Map<String, Set<String>> comps;

  CategoryIndex({required this.appstream, required this.comps});

  /// All tags (AppStream categories + comps groups) a package belongs to —
  /// i.e. every browsing bucket it would show up under. Empty means "Other".
  Set<String> tagsFor(String packageName) {
    return {...(appstream[packageName] ?? const {}), ...(comps[packageName] ?? const {})};
  }

  bool hasTag(String packageName, String tag) => tagsFor(packageName).contains(tag);

  Set<String> get allCategoryLabels =>
      {...appstream.values.expand((s) => s), ...comps.values.expand((s) => s)};
}

class CategoryService {
  /// AppStream's OS-wide RPM catalog (not just locally-installed apps) is
  /// only populated once the real `appstream-data` package is present,
  /// which PackageKit pulls in as a dependency. Fedora's own `fedora`
  /// repo doesn't ship this in its own repodata.
  static Future<bool> isFullCatalogAvailable() async {
    final result = await Process.run('rpm', ['-q', 'PackageKit']);
    return result.exitCode == 0;
  }

  /// Builds the package -> AppStream category map by querying each standard
  /// category and keeping only RPM-backed components (ones with a `Package:`
  /// line — Flatpak-bundled components have `Bundle: flatpak:...` instead
  /// and aren't relevant to a dnf-based package list).
  static Future<Map<String, Set<String>>> buildAppStreamIndex() async {
    final index = <String, Set<String>>{};
    final futures = appstreamCategories.map((category) async {
      final result = await Process.run(
        'appstreamcli',
        ['list-categories', '--details', category],
      );
      if (result.exitCode != 0) return;
      for (final block in (result.stdout as String).split('\nIdentifier:')) {
        final match = RegExp(r'^Package:\s*(\S+)', multiLine: true).firstMatch(block);
        if (match != null) {
          index.putIfAbsent(match.group(1)!, () => <String>{}).add(category);
        }
      }
    });
    await Future.wait(futures);
    return index;
  }

  /// Builds the package -> comps-group map, used as the fallback for
  /// packages with no AppStream category. Only considers user-visible
  /// groups (`dnf group list`, no --hidden) — the ~150 hidden/environment
  /// groups aren't meaningful browsing categories for an end user.
  static Future<Map<String, Set<String>>> buildCompsIndex() async {
    final listResult = await Process.run('dnf', ['group', 'list']);
    if (listResult.exitCode != 0) {
      throw Exception('dnf group list failed: ${listResult.stderr}');
    }
    final groupIds = <String>[];
    for (final line in (listResult.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final firstToken = trimmed.split(RegExp(r'\s+')).first;
      if (firstToken == 'ID') continue; // header row
      if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(firstToken)) continue;
      groupIds.add(firstToken);
    }

    final index = <String, Set<String>>{};
    final futures = groupIds.map((id) async {
      final infoResult = await Process.run('dnf', ['group', 'info', id]);
      if (infoResult.exitCode != 0) return;
      final lines = (infoResult.stdout as String).split('\n');
      String? groupName;
      bool inPackagesSection = false;
      const packageHeaders = {'Mandatory packages', 'Default packages', 'Optional packages'};
      for (final line in lines) {
        final idx = line.indexOf(':');
        if (idx == -1) continue;
        final key = line.substring(0, idx).trim();
        final value = line.substring(idx + 1).trim();
        if (key == 'Name') {
          groupName = value;
        } else if (packageHeaders.contains(key)) {
          inPackagesSection = true;
          if (value.isNotEmpty) index.putIfAbsent(value, () => <String>{}).add(groupName ?? id);
        } else if (key.isEmpty && inPackagesSection) {
          if (value.isNotEmpty) index.putIfAbsent(value, () => <String>{}).add(groupName ?? id);
        } else {
          inPackagesSection = false;
        }
      }
    });
    await Future.wait(futures);
    return index;
  }

  static Future<CategoryIndex> build() async {
    final results = await Future.wait([buildAppStreamIndex(), buildCompsIndex()]);
    return CategoryIndex(appstream: results[0], comps: results[1]);
  }
}
