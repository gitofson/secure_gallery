import 'package:shared_preferences/shared_preferences.dart';

/// Service for application settings
class SettingsService {
  static const String _keyDefaultAction = 'default_action'; // 'copy' or 'move'
  static const String _keyArchiveFolder = 'archive_folder';
  static const String _keyAuthEnabled = 'auth_enabled';
  static const String _keyStoragePath = 'storage_path';
  static const String _keySmbGalleries = 'smb_galleries';

  /// Gets the default action for image import ('copy' or 'move')
  static Future<String> getDefaultAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultAction) ?? 'copy';
  }

  /// Sets the default action for image import
  static Future<void> setDefaultAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultAction, action);
  }

  /// Gets the archive folder name
  static Future<String> getArchiveFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyArchiveFolder) ?? 'archive';
  }

  /// Sets the archive folder name
  static Future<void> setArchiveFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyArchiveFolder, folder);
  }

  /// Gets whether authentication is enabled
  static Future<bool> getAuthEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAuthEnabled) ?? false;
  }

  /// Sets whether authentication is enabled
  static Future<void> setAuthEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuthEnabled, enabled);
  }

  /// Gets the storage path (null = default internal)
  static Future<String?> getStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  /// Sets the storage path
  static Future<void> setStoragePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoragePath, path);
  }

  /// Resets the storage path to default
  static Future<void> resetStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStoragePath);
  }

  /// Gets the list of SMB galleries (JSON string)
  static Future<String?> getSmbGalleries() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySmbGalleries);
  }

  /// Sets the list of SMB galleries (JSON string)
  static Future<void> setSmbGalleries(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySmbGalleries, json);
  }
}
