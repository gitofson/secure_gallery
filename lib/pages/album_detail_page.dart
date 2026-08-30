import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/album.dart';
import '../services/storage_service.dart';
import '../services/settings_service.dart';
import 'image_viewer_page.dart';

/// Detail alba - grid obrázků
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
        
        setState(() {
          // Odstranění přesunutých obrázků ze seznamu (od konce, aby se neposunuly indexy)
          final sortedIndices = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
          for (final index in sortedIndices) {
            _images.removeAt(index);
          }
          _clearSelection();
        });
        
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
          SnackBar(content: Text('Chyba při výběru obrázku: $e')),
        );
      }
    }
  }

  Future<void> _saveImagesToAlbum(List<XFile> files) async {
    try {
      final defaultAction = await SettingsService.getDefaultAction();
      final newImages = <File>[];
      
      for (final file in files) {
        final savedFile = await _storage.saveImageToAlbum(
          widget.album.name,
          File(file.path),
        );
        newImages.add(savedFile);
        
        // Pokud je výchozí akce "move", smažeme původní soubor
        if (defaultAction == 'move') {
          try {
            await File(file.path).delete();
          } catch (e) {
            print('⚠️ Nelze smazat původní soubor: $e');
          }
        }
      }

      setState(() {
        _images.addAll(newImages);
      });
      widget.onAlbumChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Přidáno ${files.length} obrázků')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při ukládání: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat obrázek?'),
        content: const Text('Obrázek bude trvale smazán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Smazat'),
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
            SnackBar(content: Text('Chyba při mazání: $e')),
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
              title: const Text('Vybrat z galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Vybrat více obrázků'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery, multi: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Fotovat'),
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
            : null,
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
              label: const Text('Přidat'),
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
            'Album je prázdné',
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

/// Náhled obrázku v gridu (s dešifrováním a výběrem)
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
