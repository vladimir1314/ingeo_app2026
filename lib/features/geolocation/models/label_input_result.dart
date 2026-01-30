import 'dart:io';

class LabelInputResult {
  final String label;
  final String locality;
  final String coords;
  final String observation;
  final String? selectedFolderId;
  final String? selectedFolderPath;
  final List<File> photos;

  LabelInputResult({
    required this.label,
    required this.locality,
    required this.coords,
    required this.observation,
    this.selectedFolderId,
    this.selectedFolderPath,
    required this.photos,
  });
}

