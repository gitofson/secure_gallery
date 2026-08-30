import 'dart:io';

/// Model pro album (adresář obrázků)
class Album {
  final String name;
  final List<File> images;
  final bool isEncrypted;

  Album({
    required this.name,
    required this.images,
    this.isEncrypted = true,
  });
}
