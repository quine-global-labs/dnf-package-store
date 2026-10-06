import 'dart:io';

import 'package:flutter/material.dart';
import 'dnf_service.dart';
import 'category_service.dart';
import 'settings_page.dart';

void main(List<String> args) {
  runApp(const DnfPackageStoreApp());
}

class DnfPackageStoreApp extends StatelessWidget {
  const DnfPackageStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DNF Package Store',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SearchPage(),
    );
  }
}

enum Stage { search, installing, installed, failed }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _queryController = TextEditingController();
  List<PackageResult> _results = [];
  List<PackageResult>? _allPackages; // cached full listing, for local filtering
  PackageResult? _selected;
  bool _searching = false;
  String? _searchError;

  Stage _stage = Stage.search;
  final List<String> _installLog = [];
  final ScrollController _logScroll = ScrollController();
  List<LaunchTarget> _launchTargets = [];
  bool _uninstalling = false;

  bool _packageKitAvailable = false;
  bool _installingPackageKit = false;
  CategoryIndex? _categoryIndex;
  String? _activeCategory; // null = unfiltered; '' sentinel = "Other"
  bool _loadingCategoryResults = false;

  List<RepoInfo> _repos = [];
  String? _selectedRepo; // null = all enabled repos mixed together

  @override
  void initState() {
    super.initState();
    _loadCategories();
    DnfService.listRepos().then((repos) {
      if (mounted) setState(() => _repos = repos);
    });
  }

  void _onRepoChanged(String? repo) {
    setState(() {
      _selectedRepo = repo;
      _allPackages = null;
    });
    if (_activeCategory != null) {
      _filterByCategory(_activeCategory!);
    } else if (_queryController.text.trim().isNotEmpty) {
      _doSearch();
    } else if (_results.isNotEmpty) {
      _doListAll();
    }
  }

  Future<void> _loadCategories() async {
    _packageKitAvailable = await CategoryService.isFullCatalogAvailable();
    final index = await CategoryService.build();
    if (mounted) setState(() => _categoryIndex = index);
  }

  /// Package history lives outside this app now (see `pkg-history` at the
  /// repo root) — it's a plain script reading rpm-ostree deployments, with
  /// no Flutter/GTK build required. This just opens it in a terminal.
  Future<void> _openHistory() async {
    final script = File('pkg-history').absolute.path;
    if (!await File(script).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('pkg-history script not found at $script')));
      }
      return;
    }
    const terminals = [
      ['konsole', '-e'],
      ['gnome-terminal', '--'],
      ['xterm', '-e'],
    ];
    for (final terminal in terminals) {
      if ((await Process.run('which', [terminal[0]])).exitCode != 0) continue;
      try {
        await Process.start(
          terminal[0],
          [...terminal.sublist(1), 'bash', '-c', '$script; read -p "Press Enter to close..."'],
          mode: ProcessStartMode.detached,
        );
        return;
      } catch (_) {
        continue;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No terminal emulator found to show package history.')));
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    // PackageKit availability may have changed (e.g. uninstalled from Settings).
    setState(() => _categoryIndex = null);
    await _loadCategories();
  }

  Future<void> _installPackageKit() async {
    setState(() => _installingPackageKit = true);
    try {
      final exitCode = await DnfService.installTransient('PackageKit.x86_64', (_) {});
      if (exitCode == 0) {
        setState(() {
          _packageKitAvailable = true;
          _categoryIndex = null;
        });
        await _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PackageKit installed — app categories now available.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to install PackageKit.')));
      }
    } finally {
      if (mounted) setState(() => _installingPackageKit = false);
    }
  }

  /// category: a real category label, or '' as the sentinel for "Other"
  /// (packages matched by neither AppStream nor comps).
  Future<void> _filterByCategory(String category) async {
    setState(() {
      _activeCategory = category;
      _selected = null;
      _searchError = null;
      _queryController.clear();
      _stage = Stage.search;
    });
    if (_allPackages == null) {
      setState(() => _loadingCategoryResults = true);
      try {
        _allPackages = await DnfService.listAll(repo: _selectedRepo);
      } catch (e) {
        setState(() {
          _searchError = e.toString();
          _loadingCategoryResults = false;
        });
        return;
      }
    }
    final idx = _categoryIndex;
    setState(() {
      _loadingCategoryResults = false;
      if (idx == null) {
        _results = [];
      } else if (category == '') {
        _results = _allPackages!.where((p) => idx.tagsFor(p.name).isEmpty).toList();
      } else {
        _results = _allPackages!.where((p) => idx.hasTag(p.name, category)).toList();
      }
    });
  }

  Future<void> _doSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
      _allPackages = null;
      _selected = null;
      _activeCategory = null;
      _stage = Stage.search;
    });
    try {
      final results = await DnfService.search(query, repo: _selectedRepo);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _searchError = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _doListAll() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
      _allPackages = null;
      _selected = null;
      _activeCategory = null;
      _stage = Stage.search;
    });
    try {
      final all = await DnfService.listAll(repo: _selectedRepo);
      setState(() {
        _allPackages = all;
        _results = all;
      });
    } catch (e) {
      setState(() => _searchError = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  void _onQueryChanged(String value) {
    // Once the full catalog is loaded, typing filters it locally instead of
    // re-querying dnf, since that listing is already in memory.
    if (_allPackages == null) return;
    final needle = value.trim().toLowerCase();
    setState(() {
      _results = needle.isEmpty
          ? _allPackages!
          : _allPackages!
              .where((p) =>
                  p.name.toLowerCase().contains(needle) || p.summary.toLowerCase().contains(needle))
              .toList();
      _selected = null;
    });
  }

  Future<void> _doInstall() async {
    final pkg = _selected;
    if (pkg == null) return;
    setState(() {
      _stage = Stage.installing;
      _installLog.clear();
      _launchTargets = [];
    });
    try {
      final exitCode = await DnfService.installTransient(pkg.nameArch, (line) {
        setState(() => _installLog.add(line));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      });
      if (exitCode != 0) {
        setState(() => _stage = Stage.failed);
        return;
      }
      final targets = await DnfService.findLaunchTargets(pkg.name);
      setState(() {
        _launchTargets = targets;
        _stage = Stage.installed;
      });
    } catch (e) {
      setState(() {
        _installLog.add('Error: $e');
        _stage = Stage.failed;
      });
    }
  }

  Future<void> _doUninstall() async {
    final pkg = _selected;
    if (pkg == null) return;
    setState(() => _uninstalling = true);
    try {
      final exitCode = await DnfService.uninstall(pkg.nameArch, (line) {
        setState(() => _installLog.add(line));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      });
      if (exitCode == 0) {
        setState(() {
          _stage = Stage.search;
          _launchTargets = [];
        });
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${pkg.nameArch} removed.')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Uninstall failed — see log.')));
      }
    } finally {
      if (mounted) setState(() => _uninstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNF Package Store'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Package history',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Channel:'),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _selectedRepo,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All repos')),
                    for (final repo in _repos)
                      DropdownMenuItem(value: repo.id, child: Text(repo.name)),
                  ],
                  onChanged: _searching ? null : _onRepoChanged,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      labelText: _allPackages == null ? 'Search packages' : 'Filter packages',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _searching ? null : _doSearch,
                  child: _searching
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Search'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _searching ? null : _doListAll,
                  child: const Text('List All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCategoryBar(),
            const SizedBox(height: 16),
            if (_searchError != null)
              Text(_searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_allPackages != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${_results.length} of ${_allPackages!.length} packages'),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBar() {
    final idx = _categoryIndex;
    final compsLabels = idx == null ? <String>{} : idx.comps.values.expand((s) => s).toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ActionChip(
          label: const Text('Any'),
          onPressed: _searching ? null : _doListAll,
        ),
        if (idx == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (idx != null)
          for (final category in appstreamCategories)
            if (idx.appstream.values.any((tags) => tags.contains(category)))
              ChoiceChip(
                label: Text(category),
                selected: _activeCategory == category,
                onSelected: (_) => _filterByCategory(category),
              ),
        if (!_packageKitAvailable)
          ActionChip(
            avatar: _installingPackageKit
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download, size: 18),
            label: const Text('Install PackageKit for app categories'),
            onPressed: _installingPackageKit ? null : _installPackageKit,
          ),
        if (idx != null)
          for (final label in compsLabels)
            ChoiceChip(
              label: Text(label),
              selected: _activeCategory == label,
              onSelected: (_) => _filterByCategory(label),
            ),
        if (idx != null)
          ChoiceChip(
            label: const Text('Other'),
            selected: _activeCategory == '',
            onSelected: (_) => _filterByCategory(''),
          ),
        if (_loadingCategoryResults)
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  Widget _buildTags(PackageResult pkg) {
    final idx = _categoryIndex;
    if (idx == null) {
      return const SizedBox(
        height: 14,
        width: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final tags = idx.tagsFor(pkg.name).toList()..sort();
    if (tags.isEmpty) {
      return Text(
        'No category tags (shows up under "Other").',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Chip(
            label: Text(tag),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case Stage.search:
        if (_results.isEmpty) {
          return const Center(child: Text('Search for a package to begin.'));
        }
        return ListView.builder(
          itemCount: _results.length,
          itemBuilder: (context, i) {
            final pkg = _results[i];
            final selected = pkg == _selected;
            return Card(
              color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
              child: InkWell(
                onTap: () => setState(() => _selected = selected ? null : pkg),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pkg.nameArch, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(pkg.summary),
                      if (selected) ...[
                        const SizedBox(height: 10),
                        _buildTags(pkg),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: _doInstall,
                            child: const Text('Install (transient)'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      case Stage.installing:
        return _buildLog(trailing: const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        ));
      case Stage.installed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Expanded(child: Text('${_selected?.nameArch} installed (transient — gone on reboot)')),
                TextButton.icon(
                  onPressed: _uninstalling ? null : _doUninstall,
                  icon: _uninstalling
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline),
                  label: Text(_uninstalling ? 'Uninstalling...' : 'Uninstall'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Run:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_launchTargets.isEmpty)
              const Text('No runnable executable or desktop entry found for this package.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _launchTargets
                  .map((t) => FilledButton.tonalIcon(
                        onPressed: () => DnfService.launch(t),
                        icon: Icon(t.isDesktopEntry ? Icons.apps : Icons.terminal),
                        label: Text(t.label),
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
            Expanded(child: _buildLog()),
          ],
        );
      case Stage.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                const Text('Install failed.'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildLog()),
          ],
        );
    }
  }

  Widget _buildLog({Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: ListView.builder(
              controller: _logScroll,
              itemCount: _installLog.length,
              itemBuilder: (context, i) => Text(
                _installLog[i],
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
