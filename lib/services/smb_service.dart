import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smb_connect/smb_connect.dart';
import 'settings_service.dart';

/// Model for SMB gallery (configuration + state)
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

/// File on an SMB share (preview)
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

/// Service for accessing SMB galleries.
///
/// Robustness against freezing:
/// - each connection has a short timeout (8 s)
/// - each operation (list/read) has a timeout (15 s)
/// - all operations for one gallery share a single connection (lock),
///   so the server is not flooded with dozens of concurrent connections
/// - no operation blocks the UI — everything runs asynchronously
class SmbService {
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _operationTimeout = Duration(seconds: 15);

  /// One active connection per gallery + lock (operation serialization)
  static final Map<String, SmbConnect> _connections = {};
  static final Map<String, Future<void>> _locks = {};

  /// Thumbnail cache in RAM (key = file path)
  static final Map<String, Uint8List> _thumbnailCache = {};

  static const List<String> _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic',
  ];

  /// Loads the list of SMB galleries from settings
  static Future<List<SmbGallery>> loadGalleries() async {
    final json = await SettingsService.getSmbGalleries();
    if (json == null || json.isEmpty) return [];
    return SmbGallery.decodeList(json);
  }

  /// Saves the list of SMB galleries to settings
  static Future<void> saveGalleries(List<SmbGallery> galleries) async {
    await SettingsService.setSmbGalleries(SmbGallery.encodeList(galleries));
  }

  /// Gallery key for connection/lock maps
  static String _key(SmbGallery g) =>
      '${g.host}|${g.share}|${g.path}|${g.username}';

  /// Gets (or creates) a shared connection for the gallery.
  static Future<SmbConnect> _getConnection(SmbGallery gallery) async {
    final key = _key(gallery);
    final existing = _connections[key];
    if (existing != null) {
      // Don't test connection here — it can fail even when connection is alive
      // Just return it and let the operation fail if needed
      return existing;
    }

    final connect = await SmbConnect.connectAuth(
      host: gallery.host,
      username: gallery.username,
      password: gallery.password,
      domain: gallery.domain,
    ).timeout(_connectTimeout);
    _connections[key] = connect;
    return connect;
  }

  /// Closes and discards the gallery connection (after an error, so a new one is established next time).
  static Future<void> _dropConnection(SmbGallery gallery) async {
    final key = _key(gallery);
    final connect = _connections.remove(key);
    if (connect != null) {
      try {
        await connect.close();
      } catch (_) {}
    }
  }

  /// Performs an action under a lock for the given gallery — operations on a
  /// single connection are serialized (we don't flood the server or client
  /// with concurrent connections, which caused interrupted streams and blank thumbnails).
  static Future<T> _withConnection<T>(
    SmbGallery gallery,
    Future<T> Function(SmbConnect connect) action,
  ) async {
    final key = _key(gallery);
    // Wait for the previous operation for this gallery to finish
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
      // On connection error we discard it — a fresh one will be established next time
      await _dropConnection(gallery);
      rethrow;
    } finally {
      _locks.remove(key);
      completer.complete();
    }
  }

  /// Closes all connections (e.g. when leaving the SMB page)
  static Future<void> closeAll() async {
    final keys = _connections.keys.toList();
    for (final key in keys) {
      final connect = _connections.remove(key);
      try {
        await connect?.close();
      } catch (_) {}
    }
    // Also clear the thumbnail cache when closing connections
    _thumbnailCache.clear();
  }

  /// Tests connection to the SMB gallery.
  /// Returns null on success, otherwise error text to display to the user.
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

  /// Loads the list of images in the SMB gallery.
  /// On error throws an exception with a readable description (UI displays it).
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

  /// Loads content of one image from SMB (for preview/viewing).
  ///
  /// Speed optimizations (cache layers):
  /// 1. RAM cache — instant
  /// 2. Disk cache (temporary folder, survives app restart)
  /// 3. only then network read
  /// Returns null on error or incomplete data.
  static Future<Uint8List?> readImage(
      SmbGallery gallery, SmbImageFile image) async {
    // 1. RAM cache
    final cached = _thumbnailCache[image.path];
    if (cached != null) return cached;

    // 2. Disk cache (key = path hash + file size)
    final cacheFile = await _diskCacheFile(gallery, image);
    if (cacheFile != null && await cacheFile.exists()) {
      try {
        final bytes = await cacheFile.readAsBytes();
        if (_isValidImage(bytes, image.size)) {
          _thumbnailCache[image.path] = bytes;
          return bytes;
        }
        // Corrupt cache file — delete
        await cacheFile.delete();
      } catch (_) {}
    }

    // 3. Network read
    try {
      final bytes = await _withConnection(gallery, (connect) async {
        final file = await connect.file(image.path);
        final stream = await connect.openRead(file);
        // WARNING: smb_connect repeatedly yields the SAME buffer
        // (see smbOpenRead in the library) — copy:true is required, otherwise
        // all chunks point into one overwritten buffer
        // and the result is corrupt data (red square).
        final builder = BytesBuilder(copy: true);
        await for (final chunk in stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      });

      // Validation: do not cache incomplete/corrupt data
      if (!_isValidImage(bytes, image.size)) return null;

      _thumbnailCache[image.path] = bytes;
      // Save to disk for next launch (async, non-blocking)
      if (cacheFile != null) {
        cacheFile.writeAsBytes(bytes).catchError((_) => cacheFile);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// File in the disk cache for the given SMB image
  static Future<File?> _diskCacheFile(
      SmbGallery gallery, SmbImageFile image) async {
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/smb_thumbs');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      // Key: hash(host|share|path) + size (detects file change)
      final key = md5
          .convert(utf8.encode(
              '${gallery.host}|${gallery.share}|${image.path}|${image.size}'))
          .toString();
      return File('${cacheDir.path}/$key');
    } catch (_) {
      return null;
    }
  }

  /// Clears the disk thumbnail cache (e.g. on gallery refresh)
  static Future<void> clearThumbnailCache() async {
    _thumbnailCache.clear();
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/smb_thumbs');
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Basic validation of downloaded data (size + magic bytes)
  static bool _isValidImage(Uint8List bytes, int expectedSize) {
    if (bytes.isEmpty) return false;
    // If we know the expected size and data is significantly smaller, it is incomplete
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

  /// Folder path for smb_connect.
  ///
  /// WARNING: smb_connect parses the share from the first path segment
  /// (see SmbConnect.getShare), so the path MUST contain the share name:
  ///   "share" or "share/folder/subfolder"
  static String _folderPath(SmbGallery gallery) {
    final share = gallery.share.trim().replaceAll(RegExp(r'^[/\\]+'), '');
    final p = gallery.path.trim().replaceAll(RegExp(r'^[/\\]+'), '');
    if (p.isEmpty) return share;
    return '$share/$p';
  }

  /// Converts exception to readable error text
  static String _errorText(Object e) {
    var text = e.toString();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length);
    }
    if (e is TimeoutException) {
      return 'Timeout — server not responding (check host/network)';
    }
    return text;
  }
}
