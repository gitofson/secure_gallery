import 'package:shared_preferences/shared_preferences.dart';

/// Služba pro nastavení aplikace
class SettingsService {
  static const String _keyDefaultAction = 'default_action'; // 'copy' nebo 'move'
  static const String _keyArchiveFolder = 'archive_folder';
  static const String _keyAuthEnabled = 'auth_enabled';
  static const String _keyStoragePath = 'storage_path';
  static const String _keySmbGalleries = 'smb_galleries';

  /// Získá výchozí akci pro import obrázků ('copy' nebo 'move')
  static Future<String> getDefaultAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultAction) ?? 'copy';
  }

  /// Nastaví výchozí akci pro import obrázků
  static Future<void> setDefaultAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultAction, action);
  }

  /// Získá název archivní složky
  static Future<String> getArchiveFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyArchiveFolder) ?? 'archive';
  }

  /// Nastaví název archivní složky
  static Future<void> setArchiveFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyArchiveFolder, folder);
  }

  /// Získá, zda je zapnutá autentizace
  static Future<bool> getAuthEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAuthEnabled) ?? false;
  }

  /// Nastaví, zda je zapnutá autentizace
  static Future<void> setAuthEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuthEnabled, enabled);
  }

  /// Získá cestu k úložišti (null = výchozí interní)
  static Future<String?> getStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  /// Nastaví cestu k úložišti
  static Future<void> setStoragePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoragePath, path);
  }

  /// Resetuje cestu k úložišti na výchozí
  static Future<void> resetStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStoragePath);
  }

  /// Získá seznam SMB galerií (JSON string)
  static Future<String?> getSmbGalleries() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySmbGalleries);
  }

  /// Nastaví seznam SMB galerií (JSON string)
  static Future<void> setSmbGalleries(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySmbGalleries, json);
  }
}
