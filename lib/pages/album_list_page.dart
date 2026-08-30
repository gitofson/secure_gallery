import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../services/storage_service.dart';
import 'album_detail_page.dart';
import 'settings_page.dart';

/// Hlavní stránka se seznamem alb
class AlbumListPage extends StatefulWidget {
  const AlbumListPage({super.key});

  @override
  State<AlbumListPage> createState() => _AlbumListPageState();
}

class _AlbumListPageState extends State<AlbumListPage> {
  final StorageService _storage = StorageService();
  List<Album> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await _storage.loadAlbums();
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při načítání alb: $e')),
        );
      }
    }
  }

  Future<void> _createAlbum() async {
    // Vygenerovat výchozí název
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
                'Nové album',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Název alba',
                  hintText: 'např. Dovolená 2024',
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
                    child: const Text('Zrušit'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Vytvořit'),
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
            SnackBar(content: Text('Album "$result" vytvořeno')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při vytváření alba: $e')),
          );
        }
      }
    }
  }

  /// Vygeneruje výchozí název alba ve formátu g001, g002, ...
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
        title: const Text('Smazat album?'),
        content:
            Text('Album "${album.name}" a všechny jeho obrázky budou smazány.'),
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
        await _storage.deleteAlbum(album.name);
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Album "${album.name}" smazáno')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při mazání alba: $e')),
          );
        }
      }
    }
  }

  /// Zobrazí menu po dlouhém stisku na album (přejmenovat / smazat)
  void _showAlbumOptions(Album album) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Přejmenovat album'),
              onTap: () {
                Navigator.pop(context);
                _renameAlbum(album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Smazat album',
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
        title: const Text('Přejmenovat album'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nový název',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Přejmenovat'),
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
            SnackBar(content: Text('Album přejmenováno na "$result"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při přejmenování: $e')),
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
        title: const Text('Exportovat všechna alba?'),
        content: const Text(
          'Všechny obrázky ze všech alb budou dešifrovány a exportovány do systémové galerie. Tato akce může chvíli trvat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exportovat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Zobrazit progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exportuji všechna alba...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.exportAllAlbumsToGallery();

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exportováno $count obrázků')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při exportu: $e')),
          );
        }
      }
    }
  }

  Future<void> _encryptAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zašifrovat album?'),
        content: Text(
          'Album "${album.name}" obsahuje nešifrované obrázky. Chcete je zašifrovat? Tato akce může chvíli trvat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zašifrovat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Šifruji album...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.encryptAlbum(album.name);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zašifrováno $count obrázků')),
          );
          await _loadAlbums();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při šifrování: $e')),
          );
        }
      }
    }
  }

  Future<void> _decryptAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dešifrovat album?'),
        content: Text(
          'Album "${album.name}" obsahuje zašifrované obrázky. Chcete je dešifrovat a obnovit původní názvy souborů? Tato akce může chvíli trvat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dešifrovat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dešifruji album...'),
              duration: Duration(seconds: 30),
            ),
          );
        }

        final count = await _storage.decryptAlbum(album.name);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dešifrováno $count obrázků')),
          );
          await _loadAlbums();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chyba při dešifrování: $e')),
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
            icon: const Icon(Icons.download),
            tooltip: 'Exportovat všechna alba',
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
          : _albums.isEmpty
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
            'Zatím nemáte žádná alba',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vytvořte album a přidejte do něj obrázky',
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
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _AlbumCard(
          album: album,
          onTap: () => _openAlbum(album),
          onLongPress: () => _showAlbumOptions(album),
          onEncrypt: () => _encryptAlbum(album),
          onDecrypt: () => _decryptAlbum(album),
        );
      },
    );
  }
}

/// Karta alba v gridu
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
                        'Nešifrovaná data',
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
                      tooltip: 'Zašifrovat album',
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
                        'Zašifrováno',
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
                      tooltip: 'Dešifrovat album',
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
                    '${album.images.length} obrázků',
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
