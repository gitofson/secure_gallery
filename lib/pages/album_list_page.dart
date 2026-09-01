import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../services/storage_service.dart';
import '../services/smb_service.dart';
import 'album_detail_page.dart';
import 'settings_page.dart';
import 'smb_gallery_page.dart';

/// Main page with the list of albums
class AlbumListPage extends StatefulWidget {
  const AlbumListPage({super.key});

  @override
  State<AlbumListPage> createState() => _AlbumListPageState();
}

class _AlbumListPageState extends State<AlbumListPage> {
  final StorageService _storage = StorageService();
  List<Album> _albums = [];
  List<SmbGallery> _smbGalleries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      // Local albums and SMB galleries load in parallel;
      // SMB loading has a timeout, so an unavailable network does not block the UI.
      final results = await Future.wait([
        _storage.loadAlbums(),
        SmbService.loadGalleries(),
      ]);
      setState(() {
        _albums = results[0] as List<Album>;
        _smbGalleries = results[1] as List<SmbGallery>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading albums: $e')),
        );
      }
    }
  }

  Future<void> _createAlbum() async {
    // Generate default name
    final defaultName = _generateDefaultAlbumName();
    final controller = TextEditingController(text: defaultName);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New Album',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Album name',
                  hintText: 'e.g. Vacation 2024',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  Navigator.pop(context, value.trim());
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _storage.createAlbum(result);
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Album "$result" created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating album: $e')),
          );
        }
      }
    }
  }

  /// Generates a default album name in the format g001, g002, ...
  String _generateDefaultAlbumName() {
    int maxNumber = 0;

    for (final album in _albums) {
      final name = album.name;
      if (name.startsWith('g') && name.length == 4) {
        final numberStr = name.substring(1);
        final number = int.tryParse(numberStr);
        if (number != null && number > maxNumber) {
          maxNumber = number;
        }
      }
    }

    final nextNumber = maxNumber + 1;
    return 'g${nextNumber.toString().padLeft(3, '0')}';
  }

  Future<void> _deleteAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete album?'),
        content:
            Text('Album "${album.name}" and all its images will be deleted.'),
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
        await _storage.deleteAlbum(album.name);
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Album "${album.name}" deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting album: $e')),
          );
        }
      }
    }
  }

  /// Shows a menu on long-press of an album (rename / delete)
  void _showAlbumOptions(Album album) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Album'),
              onTap: () {
                Navigator.pop(context);
                _renameAlbum(album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete album',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteAlbum(album);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameAlbum(Album album) async {
    final controller = TextEditingController(text: album.name);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Album'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != album.name) {
      try {
        await _storage.renameAlbum(album.name, result);
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Album renamed to "$result"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error renaming: $e')),
          );
        }
      }
    }
  }

  void _openAlbum(Album album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumDetailPage(
          album: album,
          onAlbumChanged: _loadAlbums,
        ),
      ),
    );
  }

  Future<void> _exportAllAlbums() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export all albums?'),
        content: const Text(
          'All images from all albums will be decrypted and exported to the system gallery. This may take a while.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Show progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exporting all albums...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.exportAllAlbumsToGallery();

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported $count images')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export error: $e')),
          );
        }
      }
    }
  }

  Future<void> _encryptAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encrypt album?'),
        content: Text(
          'Album "${album.name}" contains unencrypted images. Encrypt them? This may take a while.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encrypt'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Encrypting album...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.encryptAlbum(album.name);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Encrypted $count images')),
          );
          await _loadAlbums();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Encryption error: $e')),
          );
        }
      }
    }
  }

  Future<void> _decryptAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decrypt album?'),
        content: Text(
          'Album "${album.name}" contains encrypted images. Decrypt them and restore original file names? This may take a while.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decrypt'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Decrypting album...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.decryptAlbum(album.name);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Decrypted $count images')),
          );
          await _loadAlbums();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Decryption error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Gallery'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAlbums,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export all albums',
            onPressed: _exportAllAlbums,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_albums.isEmpty && _smbGalleries.isEmpty)
              ? _buildEmptyState()
              : _buildAlbumGrid(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAlbum,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('New Album'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_album_outlined,
            size: 120,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No albums yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an album and add images to it',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumGrid() {
    final totalCount = _albums.length + _smbGalleries.length;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Local albums first, then SMB galleries
        if (index < _albums.length) {
          final album = _albums[index];
          return _AlbumCard(
            album: album,
            onTap: () => _openAlbum(album),
            onLongPress: () => _showAlbumOptions(album),
            onEncrypt: () => _encryptAlbum(album),
            onDecrypt: () => _decryptAlbum(album),
          );
        }
        final smbGallery = _smbGalleries[index - _albums.length];
        return _SmbGalleryCard(
          gallery: smbGallery,
          onTap: () => _openSmbGallery(smbGallery),
        );
      },
    );
  }

  void _openSmbGallery(SmbGallery gallery) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmbGalleryPage(gallery: gallery),
      ),
    );
  }
}

/// Album card in the grid
class _AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEncrypt;
  final VoidCallback onDecrypt;

  const _AlbumCard({
    required this.album,
    required this.onTap,
    required this.onLongPress,
    required this.onEncrypt,
    required this.onDecrypt,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: album.isEncrypted ? null : Colors.red[50],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: album.images.isNotEmpty
                  ? FutureBuilder<Uint8List>(
                      future: StorageService()
                          .loadDecryptedImage(album.images.first),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          );
                        }
                        if (snapshot.hasError) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.broken_image,
                              size: 64,
                              color: Colors.red,
                            ),
                          );
                        }
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(
                        Icons.photo_album,
                        size: 64,
                        color: Colors.grey,
                      ),
                    ),
            ),
            if (!album.isEncrypted)
              Container(
                color: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Unencrypted data',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      onPressed: onEncrypt,
                      icon: const Icon(
                        Icons.lock,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: 'Encrypt album',
                    ),
                  ],
                ),
              ),
            if (album.isEncrypted)
              Container(
                color: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Encrypted',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      onPressed: onDecrypt,
                      icon: const Icon(
                        Icons.lock_open,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'Decrypt album',
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${album.images.length} images',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SMB network gallery card in the grid
class _SmbGalleryCard extends StatelessWidget {
  final SmbGallery gallery;
  final VoidCallback onTap;

  const _SmbGalleryCard({
    required this.gallery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.blueGrey[50],
                child: const Icon(
                  Icons.folder_shared,
                  size: 64,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            Container(
              color: Colors.blueGrey,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.cloud, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Network (SMB)',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gallery.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\\\\${gallery.host}\\${gallery.share}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
