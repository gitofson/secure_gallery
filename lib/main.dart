import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/album_list_page.dart';
import 'services/encryption_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Gallery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper pro autentizaci — kontroluje, zda je zapnutá
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _hasStoragePermission = false;
  bool _authEnabled = false;
  bool _authInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Nejdřív načíst nastavení autentizace — lifecycle handlery ho potřebují
    _authEnabled = await SettingsService.getAuthEnabled();
    await _checkPermissionsAndAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Při odchodu do pozadí okamžitě skrýt obsah (žádný flash obsahu)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_authEnabled && _isAuthenticated) {
        setState(() => _isAuthenticated = false);
      }
    }

    // Po návratu z pozadí znovu vyžádat autentizaci
    if (state == AppLifecycleState.resumed &&
        _authEnabled &&
        !_isAuthenticated &&
        !_isLoading) {
      _checkAuth();
    }
  }

  Future<void> _checkPermissionsAndAuth() async {
    // Kontrola oprávnění k úložišti
    final storageStatus = await Permission.manageExternalStorage.status;
    if (storageStatus.isGranted) {
      setState(() => _hasStoragePermission = true);
    } else {
      // Vyžádání oprávnění
      final result = await Permission.manageExternalStorage.request();
      setState(() => _hasStoragePermission = result.isGranted);
    }

    // Kontrola autentizace
    await _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Inicializace šifrování až po udělení oprávnění
    if (_hasStoragePermission) {
      await EncryptionService.initialize();
    }

    _authEnabled = await SettingsService.getAuthEnabled();

    if (!_authEnabled) {
      // Autentizace není zapnutá — povolit přístup
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
      return;
    }

    // Autentizace je zapnutá — ověřit uživatele
    if (_authInProgress) return;
    _authInProgress = true;
    final authenticated = await AuthService.authenticate();
    _authInProgress = false;
    if (!mounted) return;
    setState(() {
      _isAuthenticated = authenticated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasStoragePermission) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sd_storage, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Storage Permission Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This app needs access to external storage to save your encrypted photos. '
                'Please grant "All files access" permission in system settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _checkPermissionsAndAuth,
                icon: const Icon(Icons.settings),
                label: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Authentication Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Please authenticate to access your gallery'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _checkAuth,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Authenticate'),
              ),
            ],
          ),
        ),
      );
    }

    return const AlbumListPage();
  }
}
