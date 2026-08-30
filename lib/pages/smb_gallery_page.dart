import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/smb_service.dart';
import '../services/storage_service.dart';

/// Detail SMB galerie — prohlížení a import obrázků ze síťového disku.
/// Všechny síťové operace mají timeouty, takže aplikace nikdy nezamrzne.
class SmbGalleryPage extends StatefulWidget {
  final SmbGallery gallery;

  const SmbGalleryPage({super.key, required this.gallery});

  @override
  State<SmbGalleryPage> createState() => _SmbGalleryPageState();
}

class _SmbGalleryPageState extends State<SmbGalleryPage> {
  List<SmbImageFile>? _images; // null = načítá se
  bool _loadFailed = false;
  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() {
      _images = null;
      _loadFailed = false;
    });
    final images = await SmbService.listImages(widget.gallery);
    if (!mounted) return;
    setState(() {
      _images = images;
      _loadFailed = images.isEmpty;
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) _isSelectionMode = false;
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

  /// Importuje vybrané obrázky ze SMB do lokálního šifrovaného alba
  Future<void> _importSelected() async {
    if (_selectedIndices.isEmpty || _isImporting) return;

    // Vybrat cílové album
    final albums = await StorageService().loadAlbums();
    if (!mounted) return;

    final targetAlbum = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Import into album'),
        children: [
          ...albums.map((a) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, a.name),
                child: Row(
                  children: [
                    Icon(
                      a.isEncrypted ? Icons.lock : Icons.lock_open,
                      color: a.isEncrypted ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(a.name)),
                    Text('${a.images.length}'),
                  ],
                ),
              )),
        ],
      ),
    );

    if (targetAlbum == null || !mounted) return;

    setState(() => _isImporting = true);
    int imported = 0;
    final selected = _selectedIndices.toList()..sort();

    try {
      final tempDir = await getTemporaryDirectory();
      for (final i in selected) {
        final smbImage = _images![i];
        final bytes = await SmbService.readImage(widget.gallery, smbImage);
        if (bytes == null) continue;

        // Uložit dočasně lokálně a pak importovat (zašifrovat)
        final tempFile = File('${tempDir.path}/${smbImage.name}');
        await tempFile.writeAsBytes(bytes);
        await StorageService().saveImageToAlbum(targetAlbum, tempFile);
        await tempFile.delete();
        imported++;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isImporting = false;
      });
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Imported $imported image(s) into "$targetAlbum"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIndices.length} selected')
            : Text(widget.gallery.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Import selected (encrypt into local album)',
              onPressed: _isImporting ? null : _importSelected,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel selection',
              onPressed: _clearSelection,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _loadImages,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_images == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting to network share...'),
          ],
        ),
      );
    }

    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Gallery unavailable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The network share is unreachable or empty.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadImages,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: _images!.length,
          itemBuilder: (context, index) {
            final image = _images![index];
            final isSelected = _selectedIndices.contains(index);
            return GestureDetector(
              onTap: () {
                if (_isSelectionMode) {
                  _toggleSelection(index);
                }
              },
              onLongPress: () => _toggleSelection(index),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SmbThumbnail(gallery: widget.gallery, image: image),
                  if (isSelected)
                    Container(
                      color: Colors.teal.withValues(alpha: 0.4),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (_isImporting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Importing and encrypting...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Náhled SMB obrázku — načítá se asynchronně s timeoutem
class _SmbThumbnail extends StatelessWidget {
  final SmbGallery gallery;
  final SmbImageFile image;

  const _SmbThumbnail({required this.gallery, required this.image});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: SmbService.readImage(gallery, image),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return Container(
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image, color: Colors.red),
          );
        }
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
