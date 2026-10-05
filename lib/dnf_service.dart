import 'dart:io';

class PackageResult {
  final String name;
  final String arch;
  final String summary;

  PackageResult({required this.name, required this.arch, required this.summary});

  String get nameArch => '$name.$arch';

  @override
  String toString() => nameArch;
}

class LaunchTarget {
  final String label;
  final bool isDesktopEntry;
  final String idOrPath;

  LaunchTarget({required this.label, required this.isDesktopEntry, required this.idOrPath});
}

class CommandLogger {
  final void Function(String line) onLine;
  CommandLogger(this.onLine);
}

class RepoInfo {
  final String id;
  final String name;
  RepoInfo({required this.id, required this.name});
}

class DnfService {
  /// Lists enabled repos (the "channels" a package can come from).
  static Future<List<RepoInfo>> listRepos() async {
    final result = await Process.run('dnf', ['repolist']);
    if (result.exitCode != 0) {
      throw Exception('dnf repolist failed: ${result.stderr}');
    }
    final repos = <RepoInfo>[];
    for (final line in (result.stdout as String).split('\n')) {
      if (line.startsWith('repo id')) continue; // header
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final spaceIdx = trimmed.indexOf(RegExp(r'\s'));
      if (spaceIdx == -1) continue;
      repos.add(RepoInfo(id: trimmed.substring(0, spaceIdx), name: trimmed.substring(spaceIdx).trim()));
    }
    return repos;
  }

  /// Searches package name+summary via `dnf search`. Only stdout is parsed;
  /// repo-sync progress goes to stderr on dnf5 and is ignored here.
  ///
  /// [repo] scopes the search to a single enabled repo/"channel". dnf5's
  /// `search` subcommand does NOT actually honor `--repo` (confirmed
  /// empirically: results from other repos leak through regardless), so
  /// when a repo is given this instead lists that repo via `repoquery`
  /// (which does filter correctly) and matches name/summary client-side.
  static Future<List<PackageResult>> search(String query, {String? repo}) async {
    if (repo != null) {
      final all = await listAll(repo: repo);
      final needle = query.toLowerCase();
      return all
          .where((p) =>
              p.name.toLowerCase().contains(needle) || p.summary.toLowerCase().contains(needle))
          .toList();
    }
    final result = await Process.run('dnf', ['search', query]);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw Exception('dnf search failed: ${result.stderr}');
    }
    final lines = (result.stdout as String).split('\n');
    final packages = <PackageResult>[];
    for (final rawLine in lines) {
      if (!rawLine.startsWith(' ')) continue;
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final splitIdx = line.indexOf(RegExp(r'\s'));
      if (splitIdx == -1) continue;
      final nameArch = line.substring(0, splitIdx);
      final summary = line.substring(splitIdx).trim();
      final dotIdx = nameArch.lastIndexOf('.');
      if (dotIdx == -1) continue;
      packages.add(PackageResult(
        name: nameArch.substring(0, dotIdx),
        arch: nameArch.substring(dotIdx + 1),
        summary: summary,
      ));
    }
    return packages;
  }

  /// Lists every available package (not filtered by a search term). Uses
  /// repoquery with an explicit pipe-delimited, newline-terminated format
  /// for clean parsing — unlike `dnf search`'s free-text layout. Pass
  /// [repo] to scope to a single enabled repo/"channel" instead of mixing
  /// results from all of them.
  static Future<List<PackageResult>> listAll({String? repo}) async {
    final result = await Process.run(
      'dnf',
      ['repoquery', if (repo != null) '--repo=$repo', '--available', '--qf', '%{name}.%{arch}|%{summary}\n'],
    );
    if (result.exitCode != 0) {
      throw Exception('dnf repoquery failed: ${result.stderr}');
    }
    final lines = (result.stdout as String).split('\n');
    final packages = <PackageResult>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      final barIdx = line.indexOf('|');
      if (barIdx == -1) continue;
      final nameArch = line.substring(0, barIdx);
      final summary = line.substring(barIdx + 1);
      final dotIdx = nameArch.lastIndexOf('.');
      if (dotIdx == -1) continue;
      packages.add(PackageResult(
        name: nameArch.substring(0, dotIdx),
        arch: nameArch.substring(dotIdx + 1),
        summary: summary,
      ));
    }
    return packages;
  }

  /// Installs a package transiently (overlay reset on reboot) via pkexec,
  /// which prompts through the desktop PolicyKit agent rather than needing
  /// a terminal TTY for sudo. Streams combined stdout+stderr lines.
  static Future<int> installTransient(String packageNameArch, void Function(String line) onLine) async {
    final process = await Process.start(
      'pkexec',
      ['dnf', 'install', '--transient', '-y', packageNameArch],
    );
    process.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.isNotEmpty) onLine(line);
      }
    });
    process.stderr.transform(const SystemEncoding().decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.isNotEmpty) onLine(line);
      }
    });
    return process.exitCode;
  }

  /// Removes an installed package via pkexec. Works the same whether the
  /// package was installed transiently or persistently — this just frees
  /// it up immediately rather than waiting for the transient overlay to
  /// reset on reboot. Streams combined stdout+stderr lines.
  static Future<int> uninstall(String packageNameArch, void Function(String line) onLine) async {
    final process = await Process.start(
      'pkexec',
      ['dnf', 'remove', '-y', packageNameArch],
    );
    process.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.isNotEmpty) onLine(line);
      }
    });
    process.stderr.transform(const SystemEncoding().decoder).listen((chunk) {
      for (final line in chunk.split('\n')) {
        if (line.isNotEmpty) onLine(line);
      }
    });
    return process.exitCode;
  }

  /// Finds runnable launch targets for an installed package: prefers
  /// .desktop entries (launched via gtk-launch) and falls back to raw
  /// executables under a bin/ directory.
  static Future<List<LaunchTarget>> findLaunchTargets(String packageName) async {
    final result = await Process.run('rpm', ['-ql', packageName]);
    if (result.exitCode != 0) {
      throw Exception('rpm -ql failed: ${result.stderr}');
    }
    final files = (result.stdout as String).split('\n').where((f) => f.isNotEmpty);
    final targets = <LaunchTarget>[];
    for (final file in files) {
      if (file.endsWith('.desktop') && file.contains('/applications/')) {
        final appId = file.split('/').last.replaceAll('.desktop', '');
        targets.add(LaunchTarget(label: appId, isDesktopEntry: true, idOrPath: appId));
      } else if (RegExp(r'/s?bin/').hasMatch(file) && await File(file).exists()) {
        final stat = await File(file).stat();
        final isExecutable = stat.mode & 0x49 != 0; // any execute bit
        if (isExecutable) {
          targets.add(LaunchTarget(label: file.split('/').last, isDesktopEntry: false, idOrPath: file));
        }
      }
    }
    return targets;
  }

  /// Launches a desktop entry (via gtk-launch) or a raw binary, detached
  /// from this process so closing the app doesn't kill the launched one.
  static Future<void> launch(LaunchTarget target) async {
    if (target.isDesktopEntry) {
      await Process.start('gtk-launch', [target.idOrPath], mode: ProcessStartMode.detached);
    } else {
      await Process.start(target.idOrPath, [], mode: ProcessStartMode.detached);
    }
  }
}
