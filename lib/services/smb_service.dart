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
/// - všechny operace pro jednu galerii sdílí jedno spojení (zámek),
///   takže se server nezahltí desítkami souběžných připojení
/// - každé připojení má krátký timeout (8 s)
/// - každá operace (list/read) má timeout (15 s)
/// - žádná operace neblokuje UI — vše běží asynchronně
class SmbService {
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _operationTimeout = Duration(seconds: 15);

  /// Jedno aktivní spojení na galerii + zámek (serializace operací)
  static final Map<String, SmbConnect> _connections = {};
  static final Map<String, Future<void>> _locks = {};

  /// Cache náhledů v RAM (klíč = cesta souboru)
  static final Map<String, Uint8List> _thumbnailCache = {};

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

  /// Klíč galerie pro mapy spojení/zámků
  static String _key(SmbGallery g) =>
      '${g.host}|${g.share}|${g.path}|${g.username}';

  /// Získá (nebo vytvoří) sdílené spojení pro galerii.
  static Future<SmbConnect> _getConnection(SmbGallery gallery) async {
    final key = _key(gallery);
    final existing = _connections[key];
    if (existing != null) return existing;

    final connect = await SmbConnect.connectAuth(
      host: gallery.host,
      username: gallery.username,
      password: gallery.password,
      domain: gallery.domain,
    ).timeout(_connectTimeout);
    _connections[key] = connect;
    return connect;
  }

  /// Zavře a zahodí spojení galerie (po chybě, aby se příště navázalo nové).
  static Future<void> _dropConnection(SmbGallery gallery) async {
    final key = _key(gallery);
    final connect = _connections.remove(key);
    if (connect != null) {
      try {
        await connect.close();
      } catch (_) {}
    }
  }

  /// Provede akci pod zámkem pro danou galerii — operace nad jedním
  /// spojením se serializují (server ani klient nezahltíme souběžnými
  /// připojeními, což způsobovalo přerušené streamy a bílé náhledy).
  static Future<T> _withConnection<T>(
    SmbGallery gallery,
    Future<T> Function(SmbConnect connect) action,
  ) async {
    final key = _key(gallery);
    // Počkej na dokončení předchozí operace pro tuto galerii
    while (_locks.containsKey(key)) {
      try {
        await _locks[key];
      } catch (_) {}
    }

    final completer = Completer<void>();
    _locks[key] = completer.future;
    try {
      final connect = await _getConnection(gallery);
      return await action(connect).timeout(_operationTimeout);
    } catch (e) {
      // Při chybě spojení zahodíme — příště se naváže čerstvé
      await _dropConnection(gallery);
      rethrow;
    } finally {
      _locks.remove(key);
      completer.complete();
    }
  }

  /// Uzavře všechna spojení (např. při opuštění SMB stránky)
  static Future<void> closeAll() async {
    final keys = _connections.keys.toList();
    for (final key in keys) {
      final connect = _connections.remove(key);
      try {
        await connect?.close();
      } catch (_) {}
    }
  }

  /// Otestuje připojení k SMB galerii.
  /// Vrací null při úspěchu, jinak text chyby pro zobrazení uživateli.
  static Future<String?> testConnection(SmbGallery gallery) async {
    try {
      await _withConnection(gallery, (connect) async {
        final folder = await connect.file(_folderPath(gallery));
        await connect.listFiles(folder);
        return true;
      });
      return null;
    } catch (e) {
      return _errorText(e);
    }
  }

  /// Načte seznam obrázků v SMB galerii.
  /// Při chybě vyhodí výjimku s čitelným popisem (UI ji zobrazí).
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
    } catch (e) {
      throw Exception(_errorText(e));
    }
  }

  /// Načte obsah jednoho obrázku ze SMB (pro náhled/prohlížení).
  /// Výsledek se ukládá do cache; vrací null při chybě nebo neúplných datech.
  static Future<Uint8List?> readImage(
      SmbGallery gallery, SmbImageFile image) async {
    // Cache — náhled se stáhne jen jednou
    final cached = _thumbnailCache[image.path];
    if (cached != null) return cached;

    try {
      final bytes = await _withConnection(gallery, (connect) async {
        final file = await connect.file(image.path);
        final stream = await connect.openRead(file);
        // POZOR: smb_connect yielduje opakovaně TENTÝŽ buffer
        // (viz smbOpenRead v knihovně) — copy:true je nutné, jinak
        // všechny chunky ukazují do jednoho přepisovaného bufferu
        // a výsledek jsou poškozená data (červený čtvereček).
        final builder = BytesBuilder(copy: true);
        await for (final chunk in stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      });

      // Validace: neúplná/poškozená data neukládat do cache
      if (!_isValidImage(bytes, image.size)) return null;

      _thumbnailCache[image.path] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Základní validace stažených dat (velikost + magic bytes)
  static bool _isValidImage(Uint8List bytes, int expectedSize) {
    if (bytes.isEmpty) return false;
    // Pokud známe očekávanou velikost a data jsou výrazně menší, jsou neúplná
    if (expectedSize > 0 && bytes.length < expectedSize * 0.9) return false;
    // Magic bytes: JPEG (FF D8), PNG (89 50), GIF (47 49), BMP (42 4D),
    // WEBP (52 49 46 46), HEIC (.... 66 74 79 70)
    if (bytes.length >= 4) {
      final b = bytes;
      final isJpeg = b[0] == 0xFF && b[1] == 0xD8;
      final isPng = b[0] == 0x89 && b[1] == 0x50;
      final isGif = b[0] == 0x47 && b[1] == 0x49;
      final isBmp = b[0] == 0x42 && b[1] == 0x4D;
      final isWebp = b[0] == 0x52 && b[1] == 0x49;
      final isHeic = bytes.length >= 8 && b[4] == 0x66 && b[5] == 0x74;
      if (!isJpeg && !isPng && !isGif && !isBmp && !isWebp && !isHeic) {
        return false;
      }
    }
    return true;
  }

  /// Cesta ke složce pro smb_connect.
  ///
  /// POZOR: smb_connect parsuje share z prvního segmentu cesty
  /// (viz SmbConnect.getShare), proto cesta MUSÍ obsahovat název share:
  ///   "share" nebo "share/složka/podložka"
  static String _folderPath(SmbGallery gallery) {
    final share = gallery.share.trim().replaceAll(RegExp(r'^[/\\]+'), '');
    final p = gallery.path.trim().replaceAll(RegExp(r'^[/\\]+'), '');
    if (p.isEmpty) return share;
    return '$share/$p';
  }

  /// Převede výjimku na čitelný text chyby
  static String _errorText(Object e) {
    var text = e.toString();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length);
    }
    if (e is TimeoutException) {
      return 'Timeout — server neodpovídá (zkontroluj host/síť)';
    }
    return text;
  }
}
