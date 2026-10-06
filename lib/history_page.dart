import 'package:flutter/material.dart';
import 'dnf_service.dart';

/// Standalone app (run as its own OS process/window, see main.dart's
/// `--history` flag) showing the system's dnf transaction history: every
/// applied change, which one is current, and which was the original
/// release the system was installed from.
class HistoryApp extends StatelessWidget {
  const HistoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Package History',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HistoryPage(),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry>? _entries;
  String? _error;
  final Map<int, String> _infoCache = {};
  final Set<int> _loadingInfo = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _entries = null;
      _error = null;
    });
    try {
      final entries = await DnfService.historyList();
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadInfo(int id) async {
    if (_infoCache.containsKey(id) || _loadingInfo.contains(id)) return;
    setState(() => _loadingInfo.add(id));
    try {
      final info = await DnfService.historyInfo(id);
      if (mounted) setState(() => _infoCache[id] = info);
    } catch (e) {
      if (mounted) setState(() => _infoCache[id] = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loadingInfo.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Package History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _entries == null ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error, color: Theme.of(context).colorScheme.error, size: 32),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return const Center(child: Text('No transaction history found.'));
    }

    final currentId = entries.first.id; // newest-first list
    final originalId = entries.last.id;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final isCurrent = entry.id == currentId;
        final isOriginal = entry.id == originalId;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isCurrent ? Theme.of(context).colorScheme.secondaryContainer : null,
          child: ExpansionTile(
            onExpansionChanged: (expanded) {
              if (expanded) _loadInfo(entry.id);
            },
            title: Row(
              children: [
                Text('#${entry.id}  ${entry.action}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                if (isCurrent) const _Badge(label: 'Current', color: Colors.green),
                if (isOriginal) const _Badge(label: 'Original release', color: Colors.blueGrey),
              ],
            ),
            subtitle: Text(
              '${entry.dateTime} · ${entry.commandLine.isEmpty ? '(no command line)' : entry.commandLine} · ${entry.altered} altered',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _loadingInfo.contains(entry.id)
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : SelectableText(
                          _infoCache[entry.id] ?? '',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
