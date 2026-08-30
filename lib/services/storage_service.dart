import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/album.dart';

/// Služba pro práci s úložištěm alb
class StorageService {
  static const String _albumsFolder = 'albums';

  /// Získá cestu k adresáři s alby
  Future<Directory> _getAlbumsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_albumsFolder');
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

  /// Uloží obrázek do alba
  Future<File> saveImageToAlbum(String albumName, File sourceFile) async {
    final albumsDir = await _getAlbumsDirectory();
    final albumDir = Directory('${albumsDir.path}/$albumName');
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${sourceFile.path.split('/').last}';
    return await sourceFile.copy('${albumDir.path}/$fileName');
  }

  /// Smaže obrázek
  Future<void> deleteImage(File image) async {
    if (await image.exists()) {
      await image.delete();
    }
  }

  /// Kontrola, zda je soubor obrázek
  bool isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }
}
