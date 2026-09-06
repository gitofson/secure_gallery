import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/album.dart';
import '../services/storage_service.dart';
import '../services/settings_service.dart';
import 'image_viewer_page.dart';

/// Album detail - image grid
class AlbumDetailPage extends StatefulWidget {
  final Album album;
  final VoidCallback onAlbumChanged;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.onAlbumChanged,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final ImagePicker _picker = ImagePicker();
  final StorageService _storage = StorageService();
  late List<File> _images;
  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.album.images);
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIndices.add(index);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIndices.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _moveSelectedToArchive() async {
    if (_selectedIndices.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Archive?'),
        content: Text(
          'Move ${_selectedIndices.length} selected image(s) to archive?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final selectedImages = _selectedIndices.map((i) => _images[i]).toList();
        await _storage.moveToArchive(selectedImages, widget.album.name);
        _removeSelectedFromList();
        widget.onAlbumChanged();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Moved ${selectedImages.length} image(s) to archive')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error moving to archive: $e')),
          );
        }
      }
    }
  }

  /// Removes selected images from the list (from the end, so indices don't shift)
  void _removeSelectedFromList() {
    setState(() {
      final sortedIndices = _selectedIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in sortedIndices) {
        _images.removeAt(index);
      }
      _clearSelection();
    });
  }

  /// Moves selected images to another album
  Future<void> _moveSelectedToAlbum() async {
    if (_selectedIndices.isEmpty) return;

    // Load album list (except current)
    final albums = await _storage.loadAlbums();
    final otherAlbums =
        albums.where((a) => a.name != widget.album.name).toList();

    if (!mounted) return;

    if (otherAlbums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other album exists')),
      );
      return;
    }

    final targetAlbum = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to album'),
        children: otherAlbums.map((album) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, album.name),
            child: Row(
              children: [
                Icon(
                  album.isEncrypted ? Icons.lock : Icons.lock_open,
                  size: 20,
                  color: album.isEncrypted ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(album.name)),
                Text(
                  '${album.images.length}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (targetAlbum == null) return;

    try {
      final selectedImages = _selectedIndices.map((i) => _images[i]).toList();
      final movedCount =
          await _storage.moveImagesToAlbum(selectedImages, targetAlbum);
      _removeSelectedFromList();
      widget.onAlbumChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Moved $movedCount images to "$targetAlbum"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Move error: $e')),
        );
      }
    }
  }

  Future<void> _exportSelectedImages() async {
    if (_selectedIndices.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final selectedImages = _selectedIndices.map((i) => _images[i]).toList();
      final successCount = await _storage.exportImagesToGallery(selectedImages);
      
      _clearSelection();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported $successCount image(s) to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export album?'),
        content: Text(
          'All images from album "${widget.album.name}" will be decrypted and exported to the system gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);

      try {
        final successCount = await _storage.exportImagesToGallery(_images);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported $successCount images from album "${widget.album.name}"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export error: $e')),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source, {bool multi = false}) async {
    try {
      if (multi) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (pickedFiles.isNotEmpty) {
          await _saveImagesToAlbum(pickedFiles);
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (pickedFile != null) {
          await _saveImagesToAlbum([pickedFile]);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _saveImagesToAlbum(List<XFile> files) async {
    try {
      final defaultAction = await SettingsService.getDefaultAction();
      final newImages = <File>[];
      
      // Request storage permission if we need to delete originals
      if (defaultAction == 'move') {
        PermissionStatus status;
        if (Platform.isAndroid) {
          // Check Android version and request appropriate permission
          final androidInfo = await _getAndroidVersion();
          if (androidInfo >= 33) {
            // Android 13+ (API 33+) - use READ_MEDIA_IMAGES
            status = await Permission.photos.request();
          } else {
            // Android 12 and below - use READ_EXTERNAL_STORAGE
            status = await Permission.storage.request();
          }
        } else {
          status = await Permission.photos.request();
        }
        
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission to access photos is required for move operation'),
              ),
            );
          }
          return;
        }
      }
      
      for (final file in files) {
        final savedFile = await _storage.saveImageToAlbum(
          widget.album.name,
          File(file.path),
        );
        newImages.add(savedFile);
        
        // If default action is "move", delete the original file from gallery
        if (defaultAction == 'move') {
          try {
            // For Android, we need to use content resolver to delete from gallery
            // The file.path from image_picker is a cache path, not the original
            // We need to delete using the original URI
            await _deleteOriginalFromGallery(file);
          } catch (e) {
            print('⚠️ Cannot delete original file: $e');
          }
        }
      }

      setState(() {
        _images.addAll(newImages);
      });
      widget.onAlbumChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${files.length} images')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    }
  }

  /// Deletes the original image from the system gallery
  /// Uses photo_manager to properly remove from MediaStore
  Future<void> _deleteOriginalFromGallery(XFile file) async {
    try {
      if (Platform.isAndroid) {
        // On Android, image_picker returns a cached file path
        // We need to find the original asset in MediaStore and delete it
        
        // Read the picked file content for comparison
        final pickedFile = File(file.path);
        if (!await pickedFile.exists()) {
          print('⚠️ Picked file does not exist: ${file.path}');
          return;
        }
        final pickedBytes = await pickedFile.readAsBytes();
        
        // Query all images from MediaStore
        final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          hasAll: true,
        );
        
        AssetEntity? foundAsset;
        
        // Search through all paths for our file by comparing content
        for (final path in paths) {
          final List<AssetEntity> assets = await path.getAssetListRange(
            start: 0,
            end: await path.assetCountAsync,
          );
          
          for (final asset in assets) {
            final assetFile = await asset.file;
            if (assetFile != null && await assetFile.exists()) {
              // Compare file sizes first (quick check)
              final assetSize = await assetFile.length();
              if (assetSize == pickedBytes.length) {
                // Compare content
                final assetBytes = await assetFile.readAsBytes();
                if (_listEquals(assetBytes, pickedBytes)) {
                  foundAsset = asset;
                  break;
                }
              }
            }
          }
          if (foundAsset != null) break;
        }
        
        // Delete the found asset
        if (foundAsset != null) {
          final List<String> result = await PhotoManager.editor
              .deleteWithIds([foundAsset.id]);
          if (result.isNotEmpty) {
            print('✅ Deleted original from gallery: ${foundAsset.id}');
          } else {
            print('⚠️ Failed to delete asset from gallery');
          }
        } else {
          print('⚠️ Could not find original asset in gallery');
          // Fallback: try to delete the cached file
          if (await pickedFile.exists()) {
            await pickedFile.delete();
          }
        }
      } else if (Platform.isIOS) {
        // On iOS, image_picker returns a temporary file
        // We can't delete from the photo library without additional permissions
        // Just delete the temporary file
        final tempFile = File(file.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      print('⚠️ Error deleting from gallery: $e');
      // Don't rethrow - we still want to keep the imported image
    }
  }

  /// Compares two files to check if they have the same content
  Future<bool> _compareFiles(File file1, File file2) async {
    try {
      if (!await file1.exists() || !await file2.exists()) return false;
      
      final stat1 = await file1.stat();
      final stat2 = await file2.stat();
      
      // Quick check: file size
      if (stat1.size != stat2.size) return false;
      
      // For small files, compare content directly
      if (stat1.size < 1024 * 1024) { // Less than 1MB
        final bytes1 = await file1.readAsBytes();
        final bytes2 = await file2.readAsBytes();
        return _listEquals(bytes1, bytes2);
      }
      
      // For larger files, just compare size and modification time
      return stat1.modified.isAtSameMomentAs(stat2.modified);
    } catch (e) {
      return false;
    }
  }

  /// Helper to compare two lists of bytes
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Gets Android SDK version
  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      // Use device_info_plus or similar to get SDK version
      // For now, return a default that works with photo_manager
      return 33; // Assume Android 13+ for safety
    } catch (e) {
      return 33;
    }
  }

  Future<void> _deleteImage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text('The image will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storage.deleteImage(_images[index]);
        setState(() {
          _images.removeAt(index);
        });
        widget.onAlbumChanged();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete error: $e')),
          );
        }
      }
    }
  }

  void _viewImage(int startIndex) {
    if (startIndex < 0 || startIndex >= _images.length) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewerPage(images: _images, startIndex: startIndex),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Select multiple images'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery, multi: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIndices.length} selected')
            : Text(widget.album.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.drive_file_move),
                  tooltip: 'Move to album',
                  onPressed: _moveSelectedToAlbum,
                ),
                IconButton(
                  icon: const Icon(Icons.archive),
                  tooltip: 'Move to Archive',
                  onPressed: _moveSelectedToArchive,
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Export to Gallery',
                  onPressed: _exportSelectedImages,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel Selection',
                  onPressed: _clearSelection,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Export entire album',
                  onPressed: _exportAlbum,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? _buildEmptyState()
              : _buildImageGrid(),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _showImageSourceDialog,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add'),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 120,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'Album is empty',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final isSelected = _selectedIndices.contains(index);
        return _ImageThumbnail(
          image: _images[index],
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(index);
            } else {
              _viewImage(index);
            }
          },
          onLongPress: () => _toggleSelection(index),
          onDelete: () => _deleteImage(index),
        );
      },
    );
  }
}

/// Image thumbnail in grid (with decryption and selection)
class _ImageThumbnail extends StatelessWidget {
  final File image;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _ImageThumbnail({
    required this.image,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColorFiltered(
              colorFilter: isSelected
                  ? ColorFilter.mode(
                      Colors.blue.withOpacity(0.5),
                      BlendMode.srcATop,
                    )
                  : const ColorFilter.mode(
                      Colors.transparent,
                      BlendMode.srcATop,
                    ),
              child: FutureBuilder<Uint8List>(
                future: StorageService().loadDecryptedImage(image),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    );
                  } else if (snapshot.hasError) {
                    print('❌ Thumbnail error ${image.path}: ${snapshot.error}');
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.error, color: Colors.red),
                    );
                  } else {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                },
              ),
            ),
          ),
          // Selection indicator
          if (isSelectionMode)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSelected ? Icons.check : Icons.circle_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          // Delete button (only when not in selection mode)
          if (!isSelectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
