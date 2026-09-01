import 'dart:io';

/// Model for an album (directory of images)
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
