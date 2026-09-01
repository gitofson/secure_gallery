import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/smb_service.dart';

/// Application settings page
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
  List<SmbGallery> _smbGalleries = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
    _loadStoragePath();
    _loadSmbGalleries();
  }

  Future<void> _loadSmbGalleries() async {
    final galleries = await SmbService.loadGalleries();
    setState(() => _smbGalleries = galleries);
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

  /// Dialog for adding/editing an SMB gallery
  Future<void> _editSmbGallery([SmbGallery? existing, int? index]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final hostCtrl = TextEditingController(text: existing?.host ?? '');
    final shareCtrl = TextEditingController(text: existing?.share ?? '');
    final pathCtrl = TextEditingController(text: existing?.path ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    final domainCtrl = TextEditingController(text: existing?.domain ?? '');
    bool obscurePassword = true;

    final result = await showDialog<SmbGallery>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'Add SMB Gallery' : 'Edit SMB Gallery'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Home NAS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Server (IP or hostname)',
                  hintText: 'e.g. 192.168.1.10',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: shareCtrl,
                decoration: const InputDecoration(
                  labelText: 'Share name',
                  hintText: 'e.g. photos',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Folder path (optional)',
                  hintText: 'e.g. /gallery',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword),
                  ),
                ),
                obscureText: obscurePassword,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: domainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Domain (optional)',
                  hintText: 'e.g. WORKGROUP',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  hostCtrl.text.trim().isEmpty ||
                  shareCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                SmbGallery(
                  name: nameCtrl.text.trim(),
                  host: hostCtrl.text.trim(),
                  share: shareCtrl.text.trim(),
                  path: pathCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  domain: domainCtrl.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
        ),
      ),
    );

    if (result != null) {
      final galleries = List<SmbGallery>.from(_smbGalleries);
      if (index != null) {
        galleries[index] = result;
      } else {
        galleries.add(result);
      }
      await SmbService.saveGalleries(galleries);
      await _loadSmbGalleries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SMB gallery "${result.name}" saved')),
        );
      }
    }
  }

  Future<void> _deleteSmbGallery(int index) async {
    final gallery = _smbGalleries[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove SMB gallery?'),
        content: Text('Remove "${gallery.name}" from the list? '
            'Files on the server will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final galleries = List<SmbGallery>.from(_smbGalleries)..removeAt(index);
      await SmbService.saveGalleries(galleries);
      await _loadSmbGalleries();
    }
  }

  /// Tests connection to the SMB gallery and shows the result
  Future<void> _testSmbGallery(SmbGallery gallery) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Testing connection to "${gallery.name}"...'),
          duration: const Duration(seconds: 12),
        ),
      );
    }
    final error = await SmbService.testConnection(gallery);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error == null
              ? 'Connection to "${gallery.name}" successful'
              : 'Connection failed: $error'),
          backgroundColor: error == null ? Colors.green : Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  /// Litecoin address for donations.
  /// TODO: replace with your own LTC address
  static const String ltcAddress = 'LTC_ADDRESS_PLACEHOLDER';

  /// Opens the "Buy me a coffee" PayPal link
  Future<void> _openBuyMeACoffee() async {
    final uri = Uri.parse('https://paypal.me/pastelina7');
    try {
      // First try external browser/app
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

  /// Copies the LTC address to clipboard
  Future<void> _copyLtcAddress() async {
    await Clipboard.setData(const ClipboardData(text: ltcAddress));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Litecoin address copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleAuth(bool enabled) async {
    if (enabled) {
      // Enabling authentication — verify it works
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
      // Disabling authentication
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
                // Default import action
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

                // Archive folder
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

                // Storage
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

                // SMB network galleries
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Network Galleries (SMB)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _editSmbGallery(),
                              icon: const Icon(Icons.add),
                              tooltip: 'Add SMB gallery',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Browse and import photos from SMB shares. '
                          'Network galleries are read-only; import encrypts them into local albums. '
                          'Unreachable galleries never freeze the app.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        if (_smbGalleries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No network galleries configured.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ...List.generate(_smbGalleries.length, (i) {
                            final g = _smbGalleries[i];
                            return ListTile(
                              leading: const Icon(Icons.folder_shared),
                              title: Text(g.name),
                              subtitle: Text(
                                '\\\\${g.host}\\${g.share}${g.path.isNotEmpty ? g.path : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _testSmbGallery(g),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editSmbGallery(g, i),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _deleteSmbGallery(i),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Security
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

                // Support the developer
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
                        ListTile(
                          leading: const Icon(Icons.currency_bitcoin,
                              color: Colors.blueGrey),
                          title: const Text('Donate Litecoin (LTC)'),
                          subtitle: const Text('Tap to copy address'),
                          trailing: const Icon(Icons.copy),
                          onTap: _copyLtcAddress,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // App information
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
