import 'package:local_auth/local_auth.dart';

/// Služba pro ověření uživatele (otisk prstu / Face ID / gesto)
class AuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Ověří uživatele pomocí biometrie nebo gesta
  static Future<bool> authenticate() async {
    try {
      print('🔐 AuthService.authenticate() zavoláno');
      
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      
      print('🔐 canCheckBiometrics: $canCheck');
      print('🔐 isDeviceSupported: $isDeviceSupported');

      if (!canCheck && !isDeviceSupported) {
        // Zařízení nepodporuje biometrii — povolit přístup
        print('🔐 Zařízení nepodporuje biometrii, povoluji přístup');
        return true;
      }

      print('🔐 Volám _auth.authenticate()...');
      final result = await _auth.authenticate(
        localizedReason: 'Pro přístup k galerii se ověřte',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      print('🔐 authenticate() vrátilo: $result');
      return result;
    } catch (e, stackTrace) {
      print('❌ Chyba při ověřování: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  /// Zjistí, zda zařízení podporuje biometrii
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
