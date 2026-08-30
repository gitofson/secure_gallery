import 'dart:io';

/// Model pro album (adresář obrázků)
class Album {
  final String name;
  final List<File> images;

  Album({required this.name, required this.images});
}
