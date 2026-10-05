import 'package:flutter/material.dart';
import 'category_service.dart';
import 'dnf_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _packageKitInstalled;
  bool _uninstalling = false;
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkPackageKit();
  }

  Future<void> _checkPackageKit() async {
    final installed = await CategoryService.isFullCatalogAvailable();
    if (mounted) setState(() => _packageKitInstalled = installed);
  }

  Future<void> _confirmAndUninstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall PackageKit?'),
        content: const Text(
            'This removes PackageKit and disables AppStream-based app categories until it is reinstalled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Uninstall')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _uninstalling = true;
      _log.clear();
    });
    try {
      final exitCode = await DnfService.uninstall('PackageKit', (line) {
        setState(() => _log.add(line));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      });
      await _checkPackageKit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exitCode == 0 ? 'PackageKit removed.' : 'Uninstall failed — see log.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uninstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  _packageKitInstalled == true ? Icons.check_circle : Icons.remove_circle_outline,
                  color: _packageKitInstalled == true ? Colors.green.shade600 : Colors.grey,
                ),
                title: const Text('PackageKit'),
                subtitle: Text(switch (_packageKitInstalled) {
                  null => 'Checking...',
                  true => 'Installed — powers AppStream app categories.',
                  false => 'Not installed.',
                }),
                trailing: _packageKitInstalled == true
                    ? TextButton.icon(
                        onPressed: _uninstalling ? null : _confirmAndUninstall,
                        icon: _uninstalling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.delete_outline),
                        label: Text(_uninstalling ? 'Uninstalling...' : 'Uninstall'),
                      )
                    : null,
              ),
            ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(8),
                  child: ListView.builder(
                    controller: _logScroll,
                    itemCount: _log.length,
                    itemBuilder: (context, i) => Text(
                      _log[i],
                      style:
                          const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
