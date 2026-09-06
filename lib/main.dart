import 'dart:ui';
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

/// Wrapper for authentication — checks whether it is enabled
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
  DateTime? _lastPausedTime; // Track when app went to background

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // First load authentication settings — lifecycle handlers need it
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
    // Immediately hide content when going to background (no content flash)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_authEnabled && _isAuthenticated) {
        setState(() => _isAuthenticated = false);
        _lastPausedTime = DateTime.now();
      }
    }

    // Request authentication again after returning from background
    // BUT: skip if we were in image picker (it triggers paused/resumed quickly)
    if (state == AppLifecycleState.resumed &&
        _authEnabled &&
        !_isAuthenticated &&
        !_isLoading) {
      // If we were paused for less than 2 seconds, it was probably image picker
      final pausedDuration = _lastPausedTime != null
          ? DateTime.now().difference(_lastPausedTime!)
          : Duration.zero;
      
      if (pausedDuration.inSeconds > 2) {
        _checkAuth();
      } else {
        // Short pause — probably image picker, restore auth immediately
        setState(() => _isAuthenticated = true);
      }
    }
  }

  Future<void> _checkPermissionsAndAuth() async {
    // Check storage permission
    final storageStatus = await Permission.manageExternalStorage.status;
    if (storageStatus.isGranted) {
      setState(() => _hasStoragePermission = true);
    } else {
      // Request permission
      final result = await Permission.manageExternalStorage.request();
      setState(() => _hasStoragePermission = result.isGranted);
    }

    // Check authentication
    await _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Initialize encryption only after permission is granted
    if (_hasStoragePermission) {
      await EncryptionService.initialize();
    }

    _authEnabled = await SettingsService.getAuthEnabled();

    if (!_authEnabled) {
      // Authentication is not enabled — allow access
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
      return;
    }

    // Authentication is enabled — verify the user
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background (shows app content behind blur)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: Colors.teal.shade900,
              ),
            ),
            // Lock screen content
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.teal.shade900.withValues(alpha: 0.9),
                    Colors.teal.shade700.withValues(alpha: 0.9),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App logo/icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Secure Gallery',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Authentication Required',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 48),
                    FilledButton.icon(
                      onPressed: _checkAuth,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Authenticate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const AlbumListPage();
  }
}
