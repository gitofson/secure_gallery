import 'package:local_auth/local_auth.dart';

/// Service for user authentication (fingerprint / Face ID / device credentials)
class AuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Authenticates the user using biometrics or device credentials
  static Future<bool> authenticate() async {
    try {
      print('🔐 AuthService.authenticate() called');
      
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      
      print('🔐 canCheckBiometrics: $canCheck');
      print('🔐 isDeviceSupported: $isDeviceSupported');

      if (!canCheck && !isDeviceSupported) {
        // Device does not support biometrics — allow access
        print('🔐 Device does not support biometrics, allowing access');
        return true;
      }

      print('🔐 Calling _auth.authenticate()...');
      final result = await _auth.authenticate(
        localizedReason: 'Authenticate to access the gallery',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      print('🔐 authenticate() returned: $result');
      return result;
    } catch (e, stackTrace) {
      print('❌ Authentication error: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  /// Checks whether the device supports biometrics
  static Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (e) {
      return false;
    }
  }
}
