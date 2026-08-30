import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

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
  bool _authEnabled = false;
  String _storagePath = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
    _loadStoragePath();
  }

  Future<void> _loadSettings() async {
    final action = await SettingsService.getDefaultAction();
    final folder = await SettingsService.getArchiveFolder();
    final authEnabled = await SettingsService.getAuthEnabled();
    setState(() {
      _defaultAction = action;
      _archiveFolder = folder;
      _authEnabled = authEnabled;
      _isLoading = false;
    });
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  Future<void> _loadStoragePath() async {
    final path = await StorageService().getCurrentStoragePath();
    setState(() => _storagePath = path);
  }

  Future<void> _saveDefaultAction(String action) async {
    await SettingsService.setDefaultAction(action);
    setState(() => _defaultAction = action);
  }

  Future<void> _saveArchiveFolder(String folder) async {
    await SettingsService.setArchiveFolder(folder);
    setState(() => _archiveFolder = folder);
  }

  Future<void> _saveStoragePath(String path) async {
    await SettingsService.setStoragePath(path);
    setState(() => _storagePath = path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage path updated. Restart app to apply.')),
      );
    }
  }

  Future<void> _resetStoragePath() async {
    await SettingsService.resetStoragePath();
    await _loadStoragePath();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage path reset to default')),
      );
    }
  }

  /// Otevře PayPal odkaz "Buy me a coffee"
  Future<void> _openBuyMeACoffee() async {
    final uri = Uri.parse('https://paypal.me/pastelina7');
    try {
      // Nejprve zkusit externí prohlížeč/aplikaci
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // Fallback: in-app webview
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  Future<void> _toggleAuth(bool enabled) async {
    if (enabled) {
      // Zapnutí autentizace — ověřit, že funguje
      final authenticated = await AuthService.authenticate();
      if (authenticated) {
        await SettingsService.setAuthEnabled(true);
        setState(() => _authEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication enabled')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication failed or cancelled')),
          );
        }
      }
    } else {
      // Vypnutí autentizace
      await SettingsService.setAuthEnabled(false);
      setState(() => _authEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication disabled')),
        );
      }
    }
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

                // Úložiště
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Storage Location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Where encrypted albums are stored. External storage survives app uninstall.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: TextEditingController(text: _storagePath),
                          decoration: const InputDecoration(
                            labelText: 'Storage path',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sd_storage),
                          ),
                          onSubmitted: _saveStoragePath,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _resetStoragePath,
                          icon: const Icon(Icons.restore),
                          label: const Text('Reset to default'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Zabezpečení
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Security',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Require authentication to open the app',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Enable Authentication'),
                          subtitle: const Text('Use biometrics or device credentials'),
                          value: _authEnabled,
                          onChanged: _toggleAuth,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Podpora vývojáře
                Card(
                  color: Colors.amber[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Support the Developer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'If you like this app, you can support its development.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.coffee, color: Colors.brown),
                          title: const Text('Buy me a coffee'),
                          subtitle: const Text('via PayPal'),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: _openBuyMeACoffee,
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
