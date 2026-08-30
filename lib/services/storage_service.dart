import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import '../models/album.dart';
import 'encryption_service.dart';
import 'settings_service.dart';

/// Služba pro práci s úložištěm alb (s podporou šifrování a anonymních názvů)
class StorageService {
  static const String _albumsFolder = 'albums';
  static const String _indexFileName = 'index.dat';

  /// Získá cestu k adresáři s alby
  Future<Directory> _getAlbumsDirectory() async {
    final customPath = await SettingsService.getStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      return Directory('$customPath/$_albumsFolder');
    }

    // Výchozí: public external storage (přežije odinstalaci)
    // /storage/emulated/0/SecureGallery/
    final publicDir = Directory('/storage/emulated/0/SecureGallery');
    if (await publicDir.exists() ||
        await publicDir
            .create(recursive: true)
            .then((_) => true)
            .catchError((_) => false)) {
      return Directory('${publicDir.path}/$_albumsFolder');
    }

    // Fallback: externí úložiště aplikace
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return Directory('${externalDir.path}/$_albumsFolder');
    }

    // Fallback: interní úložiště
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_albumsFolder');
  }

  /// Získá aktuální cestu k úložišti (pro zobrazení v nastavení)
  Future<String> getCurrentStoragePath() async {
    final albumsDir = await _getAlbumsDirectory();
    return albumsDir.path;
  }

  // ---------------------------------------------------------------------------
  // Index (mapování anonymních názvů na původní názvy)
  // ---------------------------------------------------------------------------

  /// Načte index z disku (dešifrovaný)
  Future<Map<String, dynamic>> _loadIndex() async {
    try {
      final albumsDir = await _getAlbumsDirectory();
      final indexFile = File('${albumsDir.path}/$_indexFileName');
      if (!await indexFile.exists()) {
        return {'albums': <String, String>{}, 'files': <String, String>{}};
      }
      final encryptedBytes = await indexFile.readAsBytes();
      final jsonString =
          utf8.decode(EncryptionService.decryptImage(encryptedBytes));
      final Map<String, dynamic> index = json.decode(jsonString);
      index['albums'] ??= <String, String>{};
      index['files'] ??= <String, String>{};
      return index;
    } catch (e) {
      print('⚠️ Chyba při načítání indexu: $e');
      return {'albums': <String, String>{}, 'files': <String, String>{}};
    }
  }

  /// Uloží index na disk (zašifrovaný)
  Future<void> _saveIndex(Map<String, dynamic> index) async {
    try {
      final albumsDir = await _getAlbumsDirectory();
      if (!await albumsDir.exists()) {
        await albumsDir.create(recursive: true);
      }
      final indexFile = File('${albumsDir.path}/$_indexFileName');
      final jsonString = json.encode(index);
      final encryptedBytes =
          EncryptionService.encryptImage(utf8.encode(jsonString));
      await indexFile.writeAsBytes(encryptedBytes, flush: true);
    } catch (e) {
      print('⚠️ Chyba při ukládání indexu: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Alba
  // ---------------------------------------------------------------------------

  /// Načte všechna alba z disku
  Future<List<Album>> loadAlbums() async {
    final albumsDir = await _getAlbumsDirectory();
    if (!await albumsDir.exists()) {
      await albumsDir.create(recursive: true);
    }

    final index = await _loadIndex();
    final albumsMap = Map<String, String>.from(index['albums'] as Map);

    final List<Album> albums = [];
    await for (final entity in albumsDir.list()) {
      if (entity is Directory) {
        final anonName = entity.path.split('/').last;
        final originalName = albumsMap[anonName] ?? anonName;
        final images = await _loadImagesFromDirectory(entity);
        final isEncrypted = await _isAlbumEncrypted(entity);
        albums.add(Album(
          name: originalName,
          images: images,
          isEncrypted: isEncrypted,
        ));
      }
    }
    return albums;
  }

  /// Zjistí, zda je album zašifrované (všechny soubory mají .enc)
  Future<bool> _isAlbumEncrypted(Directory dir) async {
    await for (final file in dir.list()) {
      if (file is File && isImageFile(file.path)) {
        if (!file.path.toLowerCase().endsWith('.enc')) {
          return false;
        }
      }
    }
    return true;
  }

  /// Načte obrázky z adresáře
  Future<List<File>> _loadImagesFromDirectory(Directory dir) async {
    final images = <File>[];
    await for (final file in dir.list()) {
      if (file is File && isImageFile(file.path)) {
        images.add(file);
      }
    }
    return images;
  }

  /// Vytvoří nové album
  Future<void> createAlbum(String name) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(name);
    final albumDir = Directory('${albumsDir.path}/$anonName');
    await albumDir.create(recursive: true);

    final index = await _loadIndex();
    (index['albums'] as Map<String, dynamic>)[anonName] = name;
    await _saveIndex(index);
  }

  /// Smaže album a všechny jeho obrázky
  Future<void> deleteAlbum(String name) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(name);
    final albumDir = Directory('${albumsDir.path}/$anonName');
    if (await albumDir.exists()) {
      await albumDir.delete(recursive: true);
    }

    final index = await _loadIndex();
    (index['albums'] as Map<String, dynamic>).remove(anonName);
    await _saveIndex(index);
  }

  // ---------------------------------------------------------------------------
  // Obrázky
  // ---------------------------------------------------------------------------

  /// Uloží obrázek do alba (zašifrovaný, anonymní název)
  Future<File> saveImageToAlbum(String albumName, File sourceFile) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonAlbumName = EncryptionService.anonymizeName(albumName);
    final albumDir = Directory('${albumsDir.path}/$anonAlbumName');
    if (!await albumDir.exists()) {
      await albumDir.create(recursive: true);
    }

    final originalFileName = sourceFile.path.split('/').last;
    final anonFileName = EncryptionService.anonymizeName(
        '${DateTime.now().millisecondsSinceEpoch}_$originalFileName');

    // Načtení a zašifrování obrázku
    final imageBytes = await sourceFile.readAsBytes();
    final encryptedBytes = EncryptionService.encryptImage(imageBytes);

    // Uložení zašifrovaného souboru
    final encryptedFile = File('${albumDir.path}/$anonFileName.enc');
    await encryptedFile.writeAsBytes(encryptedBytes);

    // Uložení mapování do indexu
    final index = await _loadIndex();
    (index['files'] as Map<String, dynamic>)[anonFileName] = originalFileName;
    await _saveIndex(index);

    return encryptedFile;
  }

  /// Načte a dešifruje obrázek (nebo vrátí nešifrovaná data)
  Future<Uint8List> loadDecryptedImage(File encryptedFile) async {
    final bytes = await encryptedFile.readAsBytes();
    if (encryptedFile.path.toLowerCase().endsWith('.enc')) {
      return EncryptionService.decryptImage(bytes);
    }
    return bytes;
  }

  /// Smaže obrázek
  Future<void> deleteImage(File image) async {
    if (await image.exists()) {
      await image.delete();
    }

    // Odstranění z indexu
    final anonFileName =
        image.path.split('/').last.replaceAll('.enc', '');
    final index = await _loadIndex();
    (index['files'] as Map<String, dynamic>).remove(anonFileName);
    await _saveIndex(index);
  }

  /// Přesune obrázky do archivního alba
  Future<void> moveToArchive(List<File> images, String sourceAlbum) async {
    final archiveFolder = await SettingsService.getArchiveFolder();
    final albumsDir = await _getAlbumsDirectory();
    final anonArchiveName = EncryptionService.anonymizeName(archiveFolder);
    final archiveDir = Directory('${albumsDir.path}/$anonArchiveName');

    if (!await archiveDir.exists()) {
      await archiveDir.create(recursive: true);
      // Zajistit, aby archivní album bylo v indexu
      final index = await _loadIndex();
      (index['albums'] as Map<String, dynamic>)[anonArchiveName] =
          archiveFolder;
      await _saveIndex(index);
    }

    for (final image in images) {
      final fileName = image.path.split('/').last;
      final newPath = '${archiveDir.path}/$fileName';
      await image.rename(newPath);
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Exportuje obrázky do systémové galerie (s původními názvy)
  Future<int> exportImagesToGallery(List<File> images) async {
    int successCount = 0;
    final index = await _loadIndex();
    final filesMap = Map<String, String>.from(index['files'] as Map);

    for (final image in images) {
      try {
        final decryptedBytes = await loadDecryptedImage(image);
        final anonFileName =
            image.path.split('/').last.replaceAll('.enc', '');
        final originalName = filesMap[anonFileName] ?? anonFileName;

        final result = await ImageGallerySaverPlus.saveImage(
          decryptedBytes,
          quality: 100,
          name: originalName,
        );

        if (result['isSuccess'] == true) {
          successCount++;
        }
      } catch (e) {
        print('❌ Chyba při exportu ${image.path}: $e');
      }
    }

    return successCount;
  }

  /// Exportuje všechna alba do systémové galerie
  Future<int> exportAllAlbumsToGallery() async {
    final albums = await loadAlbums();
    int totalExported = 0;

    for (final album in albums) {
      final count = await exportImagesToGallery(album.images);
      totalExported += count;
    }

    return totalExported;
  }

  /// Zašifruje všechny nešifrované obrázky v albu
  Future<int> encryptAlbum(String albumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(albumName);
    final albumDir = Directory('${albumsDir.path}/$anonName');

    if (!await albumDir.exists()) {
      return 0;
    }

    int encryptedCount = 0;
    final index = await _loadIndex();
    final filesMap = index['files'] as Map<String, dynamic>;

    await for (final entity in albumDir.list()) {
      if (entity is File && isImageFile(entity.path)) {
        if (!entity.path.toLowerCase().endsWith('.enc')) {
          try {
            // Načtení nešifrovaného obrázku
            final imageBytes = await entity.readAsBytes();

            // Zašifrování
            final encryptedBytes = EncryptionService.encryptImage(imageBytes);

            // Vytvoření nového anonymního názvu
            final originalFileName = entity.path.split('/').last;
            final anonFileName = EncryptionService.anonymizeName(
                '${DateTime.now().millisecondsSinceEpoch}_$originalFileName');

            // Uložení zašifrovaného souboru
            final encryptedFile =
                File('${albumDir.path}/$anonFileName.enc');
            await encryptedFile.writeAsBytes(encryptedBytes);

            // Smazání původního souboru
            await entity.delete();

            // Přidání do indexu
            filesMap[anonFileName] = originalFileName;

            encryptedCount++;
          } catch (e) {
            print('❌ Chyba při šifrování ${entity.path}: $e');
          }
        }
      }
    }

    await _saveIndex(index);
    return encryptedCount;
  }

  /// Dešifruje všechny zašifrované obrázky v albu (obnoví původní názvy)
  Future<int> decryptAlbum(String albumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(albumName);
    final albumDir = Directory('${albumsDir.path}/$anonName');

    if (!await albumDir.exists()) {
      return 0;
    }

    int decryptedCount = 0;
    final index = await _loadIndex();
    final filesMap = index['files'] as Map<String, dynamic>;

    await for (final entity in albumDir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.enc')) {
        try {
          // Načtení zašifrovaného obrázku
          final encryptedBytes = await entity.readAsBytes();

          // Dešifrování
          final decryptedBytes = EncryptionService.decryptImage(encryptedBytes);

          // Získání původního názvu z indexu
          final anonFileName =
              entity.path.split('/').last.replaceAll('.enc', '');
          final originalName = filesMap[anonFileName] ?? anonFileName;

          // Uložení dešifrovaného souboru s původním názvem
          final decryptedFile = File('${albumDir.path}/$originalName');
          await decryptedFile.writeAsBytes(decryptedBytes);

          // Smazání zašifrovaného souboru
          await entity.delete();

          // Odstranění z indexu
          filesMap.remove(anonFileName);

          decryptedCount++;
        } catch (e) {
          print('❌ Chyba při dešifrování ${entity.path}: $e');
        }
      }
    }

    await _saveIndex(index);
    return decryptedCount;
  }

  // ---------------------------------------------------------------------------
  // Pomocné metody
  // ---------------------------------------------------------------------------

  /// Kontrola, zda je soubor obrázek (včetně .enc)
  bool isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'enc'].contains(ext);
  }
}
