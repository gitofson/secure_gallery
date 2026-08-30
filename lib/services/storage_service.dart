import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import '../models/album.dart';
import 'encryption_service.dart';
import 'settings_service.dart';

/// Služba pro práci s úložištěm alb (s podporou šifrování)
class StorageService {
  static const String _albumsFolder = 'albums';

  /// Získá cestu k adresáři s alby
  Future<Directory> _getAlbumsDirectory() async {
    final customPath = await SettingsService.getStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      return Directory('$customPath/$_albumsFolder');
    }
    
    // Výchozí: externí úložiště (přežije odinstalaci)
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

  /// Načte všechna alba z disku
  Future<List<Album>> loadAlbums() async {
    final albumsDir = await _getAlbumsDirectory();
    if (!await albumsDir.exists()) {
      await albumsDir.create(recursive: true);
    }

    final List<Album> albums = [];
    await for (final entity in albumsDir.list()) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        final images = await _loadImagesFromDirectory(entity);
        albums.add(Album(name: name, images: images));
      }
    }
    return albums;
  }

  /// Načte obrázky z adresáře (dešifrované)
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
    final albumDir = Directory('${albumsDir.path}/$name');
    await albumDir.create(recursive: true);
  }

  /// Smaže album a všechny jeho obrázky
  Future<void> deleteAlbum(String name) async {
    final albumsDir = await _getAlbumsDirectory();
    final albumDir = Directory('${albumsDir.path}/$name');
    if (await albumDir.exists()) {
      await albumDir.delete(recursive: true);
    }
  }

  /// Uloží obrázek do alba (zašifrovaný)
  Future<File> saveImageToAlbum(String albumName, File sourceFile) async {
    final albumsDir = await _getAlbumsDirectory();
    final albumDir = Directory('${albumsDir.path}/$albumName');
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${sourceFile.path.split('/').last}';
    
    // Načtení a zašifrování obrázku
    final imageBytes = await sourceFile.readAsBytes();
    final encryptedBytes = EncryptionService.encryptImage(imageBytes);
    
    // Uložení zašifrovaného souboru
    final encryptedFile = File('${albumDir.path}/$fileName.enc');
    await encryptedFile.writeAsBytes(encryptedBytes);
    
    return encryptedFile;
  }

  /// Načte a dešifruje obrázek
  Future<Uint8List> loadDecryptedImage(File encryptedFile) async {
    final encryptedBytes = await encryptedFile.readAsBytes();
    return EncryptionService.decryptImage(encryptedBytes);
  }

  /// Smaže obrázek
  Future<void> deleteImage(File image) async {
    if (await image.exists()) {
      await image.delete();
    }
  }

  /// Přesune obrázky do archivního alba
  Future<void> moveToArchive(List<File> images, String sourceAlbum) async {
    final archiveFolder = await SettingsService.getArchiveFolder();
    final albumsDir = await _getAlbumsDirectory();
    final archiveDir = Directory('${albumsDir.path}/$archiveFolder');
    
    if (!await archiveDir.exists()) {
      await archiveDir.create(recursive: true);
    }

    for (final image in images) {
      final fileName = image.path.split('/').last;
      final newPath = '${archiveDir.path}/$fileName';
      await image.rename(newPath);
    }
  }

  /// Exportuje obrázky do systémové galerie
  Future<int> exportImagesToGallery(List<File> images) async {
    int successCount = 0;
    
    for (final image in images) {
      try {
        final decryptedBytes = await loadDecryptedImage(image);
        final fileName = image.path.split('/').last.replaceAll('.enc', '');
        
        final result = await ImageGallerySaverPlus.saveImage(
          decryptedBytes,
          quality: 100,
          name: fileName,
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

  /// Kontrola, zda je soubor obrázek (včetně .enc)
  bool isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'enc'].contains(ext);
  }
}
