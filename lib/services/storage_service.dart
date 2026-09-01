import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import '../models/album.dart';
import 'encryption_service.dart';
import 'settings_service.dart';

/// Service for album storage (with encryption and anonymous names support)
class StorageService {
  static const String _albumsFolder = 'albums';
  static const String _indexFileName = 'index.dat';

  /// Gets the path to the albums directory
  Future<Directory> _getAlbumsDirectory() async {
    final customPath = await SettingsService.getStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      return Directory('$customPath/$_albumsFolder');
    }

    // Default: public external storage (survives uninstall)
    // /storage/emulated/0/SecureGallery/
    final publicDir = Directory('/storage/emulated/0/SecureGallery');
    if (await publicDir.exists() ||
        await publicDir
            .create(recursive: true)
            .then((_) => true)
            .catchError((_) => false)) {
      return Directory('${publicDir.path}/$_albumsFolder');
    }

    // Fallback: app external storage
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return Directory('${externalDir.path}/$_albumsFolder');
    }

    // Fallback: internal storage
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_albumsFolder');
  }

  /// Gets the current storage path (for display in settings)
  Future<String> getCurrentStoragePath() async {
    final albumsDir = await _getAlbumsDirectory();
    return albumsDir.path;
  }

  // ---------------------------------------------------------------------------
  // Index (mapping of anonymous names to original names)
  // ---------------------------------------------------------------------------

  /// Loads the index from disk (decrypted)
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
      print('⚠️ Error loading index: $e');
      return {'albums': <String, String>{}, 'files': <String, String>{}};
    }
  }

  /// Saves the index to disk (encrypted)
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
      print('⚠️ Error saving index: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  /// Loads all albums from disk
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

  /// Checks whether the album is encrypted (all files have .enc)
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

  /// Loads images from a directory
  Future<List<File>> _loadImagesFromDirectory(Directory dir) async {
    final images = <File>[];
    await for (final file in dir.list()) {
      if (file is File && isImageFile(file.path)) {
        images.add(file);
      }
    }
    return images;
  }

  /// Finds the actual album directory — anonymous (hash) or plain name
  /// (manually copied albums keep their original name on disk)
  Future<Directory?> _resolveAlbumDir(String albumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonDir =
        Directory('${albumsDir.path}/${EncryptionService.anonymizeName(albumName)}');
    if (await anonDir.exists()) return anonDir;
    final plainDir = Directory('${albumsDir.path}/$albumName');
    if (await plainDir.exists()) return plainDir;
    return null;
  }

  /// Creates a new album
  Future<void> createAlbum(String name) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(name);
    final albumDir = Directory('${albumsDir.path}/$anonName');
    await albumDir.create(recursive: true);

    final index = await _loadIndex();
    (index['albums'] as Map<String, dynamic>)[anonName] = name;
    await _saveIndex(index);
  }

  /// Deletes an album and all its images
  Future<void> deleteAlbum(String name) async {
    final anonName = EncryptionService.anonymizeName(name);
    final albumDir = await _resolveAlbumDir(name);
    if (albumDir != null) {
      await albumDir.delete(recursive: true);
    }

    final index = await _loadIndex();
    (index['albums'] as Map<String, dynamic>).remove(anonName);
    await _saveIndex(index);
  }

  // ---------------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------------

  /// Saves an image to an album (encrypted, anonymous name)
  Future<File> saveImageToAlbum(String albumName, File sourceFile) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonAlbumName = EncryptionService.anonymizeName(albumName);
    final albumDir = await _resolveAlbumDir(albumName) ??
        Directory('${albumsDir.path}/$anonAlbumName');
    if (!await albumDir.exists()) {
      await albumDir.create(recursive: true);
    }

    final originalFileName = sourceFile.path.split('/').last;
    final anonFileName = EncryptionService.anonymizeName(
        '${DateTime.now().millisecondsSinceEpoch}_$originalFileName');

    // Load and encrypt the image
    final imageBytes = await sourceFile.readAsBytes();
    final encryptedBytes = EncryptionService.encryptImage(imageBytes);

    // Save the encrypted file
    final encryptedFile = File('${albumDir.path}/$anonFileName.enc');
    await encryptedFile.writeAsBytes(encryptedBytes);

    // Save the mapping to the index
    final index = await _loadIndex();
    (index['files'] as Map<String, dynamic>)[anonFileName] = originalFileName;
    await _saveIndex(index);

    return encryptedFile;
  }

  /// Loads and decrypts an image (or returns unencrypted data)
  Future<Uint8List> loadDecryptedImage(File encryptedFile) async {
    final bytes = await encryptedFile.readAsBytes();
    if (encryptedFile.path.toLowerCase().endsWith('.enc')) {
      return EncryptionService.decryptImage(bytes);
    }
    return bytes;
  }

  /// Deletes an image
  Future<void> deleteImage(File image) async {
    if (await image.exists()) {
      await image.delete();
    }

    // Remove from the index
    final anonFileName =
        image.path.split('/').last.replaceAll('.enc', '');
    final index = await _loadIndex();
    (index['files'] as Map<String, dynamic>).remove(anonFileName);
    await _saveIndex(index);
  }

  /// Moves images to the archive album
  Future<void> moveToArchive(List<File> images, String sourceAlbum) async {
    final archiveFolder = await SettingsService.getArchiveFolder();
    await moveImagesToAlbum(images, archiveFolder);
  }

  /// Renames an album (directory and index record)
  Future<void> renameAlbum(String oldName, String newName) async {
    if (oldName == newName || newName.isEmpty) return;

    final albumsDir = await _getAlbumsDirectory();
    final oldAnon = EncryptionService.anonymizeName(oldName);
    final newAnon = EncryptionService.anonymizeName(newName);

    final oldDir = await _resolveAlbumDir(oldName);
    if (oldDir == null) return;

    final newDir = Directory('${albumsDir.path}/$newAnon');
    if (await newDir.exists()) {
      throw Exception('Album named "$newName" already exists');
    }

    // Rename the directory (always to the anonymous name of the new album)
    await oldDir.rename(newDir.path);

    // Update the index
    final index = await _loadIndex();
    final albumsMap = index['albums'] as Map<String, dynamic>;
    albumsMap.remove(oldAnon);
    albumsMap[newAnon] = newName;
    await _saveIndex(index);
  }

  /// Moves images to another album.
  /// Encrypted and unencrypted photos are never mixed in one album:
  /// - Target encrypted + source unencrypted → photo is encrypted (anonymous name)
  /// - Target unencrypted + source encrypted → photo is decrypted (original name)
  /// - Same state → moved as is
  Future<int> moveImagesToAlbum(List<File> images, String targetAlbumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonTarget = EncryptionService.anonymizeName(targetAlbumName);
    final targetDir = await _resolveAlbumDir(targetAlbumName) ??
        Directory('${albumsDir.path}/$anonTarget');

    final index = await _loadIndex();
    final albumsMap = index['albums'] as Map<String, dynamic>;
    final filesMap = index['files'] as Map<String, dynamic>;

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      albumsMap[anonTarget] = targetAlbumName;
    }

    // Check whether the target album is encrypted
    final targetEncrypted = await _isAlbumEncrypted(targetDir);

    int movedCount = 0;
    for (final image in images) {
      try {
        final fileName = image.path.split('/').last;
        final isEncrypted = fileName.toLowerCase().endsWith('.enc');
        final anonFileName = fileName.replaceAll('.enc', '');

        if (isEncrypted && !targetEncrypted) {
          // Target unencrypted → decrypt and save under the original name
          final decrypted = EncryptionService.decryptImage(
              await image.readAsBytes());
          final originalName = filesMap[anonFileName] ?? anonFileName;
          final targetFile = File('${targetDir.path}/$originalName');
          await targetFile.writeAsBytes(decrypted);
          await image.delete();
          filesMap.remove(anonFileName);
        } else if (!isEncrypted && targetEncrypted) {
          // Target encrypted → encrypt and save under an anonymous name
          final imageBytes = await image.readAsBytes();
          final encryptedBytes = EncryptionService.encryptImage(imageBytes);
          final newAnonName = EncryptionService.anonymizeName(
              '${DateTime.now().millisecondsSinceEpoch}_$fileName');
          final targetFile = File('${targetDir.path}/$newAnonName.enc');
          await targetFile.writeAsBytes(encryptedBytes);
          await image.delete();
          filesMap[newAnonName] = fileName;
        } else {
          // Same state → move as is
          final newPath = '${targetDir.path}/$fileName';
          await image.rename(newPath);
        }
        movedCount++;
      } catch (e) {
        print('❌ Error moving ${image.path}: $e');
      }
    }

    await _saveIndex(index);
    return movedCount;
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Exports images to the system gallery (with original names)
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
        print('❌ Error exporting ${image.path}: $e');
      }
    }

    return successCount;
  }

  /// Exports all albums to the system gallery
  Future<int> exportAllAlbumsToGallery() async {
    final albums = await loadAlbums();
    int totalExported = 0;

    for (final album in albums) {
      final count = await exportImagesToGallery(album.images);
      totalExported += count;
    }

    return totalExported;
  }

  /// Encrypts all unencrypted images in the album
  Future<int> encryptAlbum(String albumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(albumName);
    final albumDir = await _resolveAlbumDir(albumName);

    if (albumDir == null) {
      return 0;
    }

    int encryptedCount = 0;
    final index = await _loadIndex();
    final filesMap = index['files'] as Map<String, dynamic>;

    // First load the file list (do not modify the directory during iteration)
    final entities = await albumDir.list().toList();

    for (final entity in entities) {
      if (entity is File && isImageFile(entity.path)) {
        if (!entity.path.toLowerCase().endsWith('.enc')) {
          try {
            // Load the unencrypted image
            final imageBytes = await entity.readAsBytes();

            // Encrypt
            final encryptedBytes = EncryptionService.encryptImage(imageBytes);

            // Create a new anonymous name
            final originalFileName = entity.path.split('/').last;
            final anonFileName = EncryptionService.anonymizeName(
                '${DateTime.now().millisecondsSinceEpoch}_$originalFileName');

            // Save the encrypted file
            final encryptedFile = File('${albumDir.path}/$anonFileName.enc');
            await encryptedFile.writeAsBytes(encryptedBytes);

            // Delete the original file
            await entity.delete();

            // Add to the index
            filesMap[anonFileName] = originalFileName;

            encryptedCount++;
          } catch (e) {
            print('❌ Error encrypting ${entity.path}: $e');
          }
        }
      }
    }

    // Manually copied album (plain name) — rename to anonymous
    if (albumDir.path.split('/').last != anonName) {
      try {
        await albumDir.rename('${albumsDir.path}/$anonName');
        (index['albums'] as Map<String, dynamic>)[anonName] = albumName;
      } catch (e) {
        print('⚠️ Error renaming album directory: $e');
      }
    }

    await _saveIndex(index);
    return encryptedCount;
  }

  /// Decrypts all encrypted images in the album (restores original names)
  Future<int> decryptAlbum(String albumName) async {
    final albumsDir = await _getAlbumsDirectory();
    final anonName = EncryptionService.anonymizeName(albumName);
    final albumDir = await _resolveAlbumDir(albumName);

    if (albumDir == null) {
      return 0;
    }

    int decryptedCount = 0;
    final index = await _loadIndex();
    final filesMap = index['files'] as Map<String, dynamic>;

    // First load the file list (do not modify the directory during iteration)
    final entities = await albumDir.list().toList();

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.enc')) {
        try {
          // Load the encrypted image
          final encryptedBytes = await entity.readAsBytes();

          // Decrypt
          final decryptedBytes = EncryptionService.decryptImage(encryptedBytes);

          // Get the original name from the index
          final anonFileName =
              entity.path.split('/').last.replaceAll('.enc', '');
          final originalName = filesMap[anonFileName] ?? anonFileName;

          // Save the decrypted file with the original name
          final decryptedFile = File('${albumDir.path}/$originalName');
          await decryptedFile.writeAsBytes(decryptedBytes);

          // Delete the encrypted file
          await entity.delete();

          // Remove from the index
          filesMap.remove(anonFileName);

          decryptedCount++;
        } catch (e) {
          print('❌ Error decrypting ${entity.path}: $e');
        }
      }
    }

    // Rename the anonymous directory back to the original album name
    if (albumDir.path.split('/').last == anonName && anonName != albumName) {
      final plainDir = Directory('${albumsDir.path}/$albumName');
      if (!await plainDir.exists()) {
        try {
          await albumDir.rename(plainDir.path);
          (index['albums'] as Map<String, dynamic>).remove(anonName);
        } catch (e) {
          print('⚠️ Error renaming album directory: $e');
        }
      }
    }

    await _saveIndex(index);
    return decryptedCount;
  }

  // ---------------------------------------------------------------------------
  // Helper methods
  // ---------------------------------------------------------------------------

  /// Checks whether a file is an image (including .enc)
  bool isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'enc'].contains(ext);
  }
}
