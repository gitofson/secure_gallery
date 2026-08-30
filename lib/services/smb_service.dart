import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:smb_connect/smb_connect.dart';
import 'settings_service.dart';

/// Model pro SMB galerii (konfigurace + stav)
class SmbGallery {
  final String name;
  final String host;
  final String share;
  final String path;
  final String username;
  final String password;
  final String domain;

  const SmbGallery({
    required this.name,
    required this.host,
    required this.share,
    this.path = '',
    this.username = '',
    this.password = '',
    this.domain = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'share': share,
        'path': path,
        'username': username,
        'password': password,
        'domain': domain,
      };

  factory SmbGallery.fromJson(Map<String, dynamic> json) => SmbGallery(
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        share: json['share'] as String? ?? '',
        path: json['path'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
      );

  static String encodeList(List<SmbGallery> galleries) =>
      jsonEncode(galleries.map((g) => g.toJson()).toList());

  static List<SmbGallery> decodeList(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => SmbGallery.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// Soubor na SMB sdílení (náhled)
class SmbImageFile {
  final String name;
  final String path;
  final int size;

  const SmbImageFile({
    required this.name,
    required this.path,
    required this.size,
  });
}

/// Služba pro přístup k SMB galeriím.
///
/// Robustnost proti mrznutí:
/// - každé připojení má krátký timeout (8 s)
/// - každá operace (list/read) má timeout (10 s)
/// - připojení se použije jednorázově a vždy se zavře
/// - žádná operace neblokuje UI — vše běží asynchronně
class SmbService {
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _operationTimeout = Duration(seconds: 10);

  static const List<String> _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic',
  ];

  /// Načte seznam SMB galerií z nastavení
  static Future<List<SmbGallery>> loadGalleries() async {
    final json = await SettingsService.getSmbGalleries();
    if (json == null || json.isEmpty) return [];
    return SmbGallery.decodeList(json);
  }

  /// Uloží seznam SMB galerií do nastavení
  static Future<void> saveGalleries(List<SmbGallery> galleries) async {
    await SettingsService.setSmbGalleries(SmbGallery.encodeList(galleries));
  }

  /// Připojí se k SMB serveru, provede akci a odpojí se.
  /// Vždy zavře spojení, i při chybě. Timeout na připojení i operaci.
  static Future<T> _withConnection<T>(
    SmbGallery gallery,
    Future<T> Function(SmbConnect connect) action,
  ) async {
    SmbConnect? connect;
    try {
      connect = await SmbConnect.connectAuth(
        host: gallery.host,
        username: gallery.username,
        password: gallery.password,
        domain: gallery.domain,
      ).timeout(_connectTimeout);

      return await action(connect).timeout(_operationTimeout);
    } finally {
      try {
        await connect?.close();
      } catch (_) {
        // Ignorovat chyby při zavírání
      }
    }
  }

  /// Otestuje připojení k SMB galerii (true = dostupná)
  static Future<bool> testConnection(SmbGallery gallery) async {
    try {
      await _withConnection(gallery, (connect) async {
        final folder = await connect.file(_folderPath(gallery));
        await connect.listFiles(folder);
        return true;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Načte seznam obrázků v SMB galerii.
  /// Vrací prázdný seznam při jakékoli chybě (nedostupná síť apod.).
  static Future<List<SmbImageFile>> listImages(SmbGallery gallery) async {
    try {
      return await _withConnection(gallery, (connect) async {
        final folder = await connect.file(_folderPath(gallery));
        final files = await connect.listFiles(folder);
        return files
            .where((f) =>
                f.isFile() &&
                _imageExtensions.any(
                    (ext) => f.name.toLowerCase().endsWith(ext)))
            .map((f) => SmbImageFile(
                  name: f.name,
                  path: f.path,
                  size: f.size,
                ))
            .toList();
      });
    } catch (_) {
      return [];
    }
  }

  /// Načte obsah jednoho obrázku ze SMB (pro náhled/prohlížení).
  /// Vrací null při chybě.
  static Future<Uint8List?> readImage(
      SmbGallery gallery, SmbImageFile image) async {
    try {
      return await _withConnection(gallery, (connect) async {
        final file = await connect.file(image.path);
        final stream = await connect.openRead(file);
        final builder = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      });
    } catch (_) {
      return null;
    }
  }

  /// Cesta ke složce v rámci share ("/" pokud je path prázdná)
  static String _folderPath(SmbGallery gallery) {
    final p = gallery.path.trim();
    if (p.isEmpty || p == '/') return '/';
    return p.startsWith('/') ? p : '/$p';
  }
}
