import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';

/// Stránka nastavení aplikace
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _defaultAction = 'copy';
  String _archiveFolder = 'archive';
  bool _isLoading = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
  }

  Future<void> _loadSettings() async {
    final action = await SettingsService.getDefaultAction();
    final folder = await SettingsService.getArchiveFolder();
    setState(() {
      _defaultAction = action;
      _archiveFolder = folder;
      _isLoading = false;
    });
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  Future<void> _saveDefaultAction(String action) async {
    await SettingsService.setDefaultAction(action);
    setState(() => _defaultAction = action);
  }

  Future<void> _saveArchiveFolder(String folder) async {
    await SettingsService.setArchiveFolder(folder);
    setState(() => _archiveFolder = folder);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Výchozí akce při importu
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Default Import Action',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose whether to copy or move images when importing',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'copy',
                              label: Text('Copy'),
                              icon: Icon(Icons.copy),
                            ),
                            ButtonSegment(
                              value: 'move',
                              label: Text('Move'),
                              icon: Icon(Icons.move_to_inbox),
                            ),
                          ],
                          selected: {_defaultAction},
                          onSelectionChanged: (Set<String> newSelection) {
                            _saveDefaultAction(newSelection.first);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Archivní složka
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Archive Folder',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Name of the folder for archived images',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: TextEditingController(text: _archiveFolder),
                          decoration: const InputDecoration(
                            labelText: 'Folder name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.folder),
                          ),
                          onSubmitted: _saveArchiveFolder,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Informace o aplikaci
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const ListTile(
                          leading: Icon(Icons.photo_library),
                          title: Text('Secure Gallery'),
                          subtitle: Text('Encrypted photo gallery'),
                        ),
                        const ListTile(
                          leading: Icon(Icons.lock),
                          title: Text('Encryption'),
                          subtitle: Text('AES-256 with secure key storage'),
                        ),
                        const ListTile(
                          leading: Icon(Icons.fingerprint),
                          title: Text('Authentication'),
                          subtitle: Text('Biometric or device credentials'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.info),
                          title: const Text('Version'),
                          subtitle: Text(_appVersion),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
