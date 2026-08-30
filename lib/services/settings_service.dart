import 'package:shared_preferences/shared_preferences.dart';

/// Služba pro nastavení aplikace
class SettingsService {
  static const String _keyDefaultAction = 'default_action'; // 'copy' nebo 'move'
  static const String _keyArchiveFolder = 'archive_folder';

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
}
