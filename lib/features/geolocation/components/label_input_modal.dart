import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:ingeo_app/models/folder.dart';
import 'package:ingeo_app/core/services/elevation_service.dart';

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

class LabelInputModal extends StatefulWidget {
  final String drawingType;
  final LatLng centerPosition;
  final List<Folder> availableFolders;
  final Future<Folder> Function(String name) onFolderCreate;
  final String Function(LatLng position) getUTMCoordinates;
  final Future<File> Function(
    File image,
    String label,
    String utm,
    int altitude,
  )
  annotateImage;
  final Function(LabelInputResult result) onSave;
  final Widget Function(String label, String value) buildLocationInfoRow;

  const LabelInputModal({
    Key? key,
    required this.drawingType,
    required this.centerPosition,
    required this.availableFolders,
    required this.onFolderCreate,
    required this.getUTMCoordinates,
    required this.annotateImage,
    required this.onSave,
    required this.buildLocationInfoRow,
  }) : super(key: key);

  @override
  State<LabelInputModal> createState() => _LabelInputModalState();
}

class _LabelInputModalState extends State<LabelInputModal> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _localityController = TextEditingController();
  final TextEditingController _folderNameController = TextEditingController();
  final TextEditingController _coordsController = TextEditingController();
  final TextEditingController _observacionController = TextEditingController();

  List<File> photosTemp = [];
  late List<Folder> availableFolders;
  String? selectedFolderId;
  String? selectedFolderPath;

  @override
  void initState() {
    super.initState();
    availableFolders = List.from(widget.availableFolders);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _localityController.dispose();
    _folderNameController.dispose();
    _coordsController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double currentLat = widget.centerPosition.latitude;
    final double currentLng = widget.centerPosition.longitude;
    final String utmCoords = widget.getUTMCoordinates(widget.centerPosition);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.drawingType == 'line'
                    ? 'Etiqueta de Línea'
                    : widget.drawingType == 'polygon'
                    ? 'Etiqueta de Polígono'
                    : 'Etiqueta de Punto',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Sección de carpetas
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (selectedFolderId != null)
                      ? Colors.green.withOpacity(0.04)
                      : Colors.red.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (selectedFolderId != null)
                        ? Colors.green
                        : Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          (selectedFolderId != null)
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          color: (selectedFolderId != null)
                              ? Colors.green
                              : Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Seleccionar la Carpeta de Destino',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (selectedFolderId != null)
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                ((selectedFolderId != null)
                                        ? Colors.green
                                        : Colors.redAccent)
                                    .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (selectedFolderId != null)
                                  ? Colors.green
                                  : Colors.redAccent,
                            ),
                          ),
                          child: Text(
                            (selectedFolderId != null)
                                ? 'Seleccionado'
                                : 'Obligatorio',
                            style: TextStyle(
                              color: (selectedFolderId != null)
                                  ? Colors.green
                                  : Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Selector de carpeta existente
                    if (availableFolders.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: (selectedFolderId != null)
                                ? Colors.green
                                : Colors.redAccent,
                            width: 1.2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: DropdownButton<String>(
                          value: selectedFolderId,
                          isExpanded: true,
                          hint: const Text(
                            'Seleccione una carpeta (obligatorio)',
                          ),
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Ninguna (raíz)'),
                            ),
                            ...availableFolders.map((folder) {
                              return DropdownMenuItem<String>(
                                value: folder.id,
                                child: Text(folder.name),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedFolderId = value;
                              if (value != null) {
                                selectedFolderPath = availableFolders
                                    .firstWhere((f) => f.id == value)
                                    .name;
                              } else {
                                selectedFolderPath = null;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Crear nueva carpeta
                    ExpansionTile(
                      title: const Text('Crear nueva carpeta'),
                      children: [
                        TextField(
                          controller: _folderNameController,
                          decoration: const InputDecoration(
                            hintText: 'Nombre de la carpeta',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () async {
                            if (_folderNameController.text.trim().isNotEmpty) {
                              final newFolder = await widget.onFolderCreate(
                                _folderNameController.text.trim(),
                              );
                              setState(() {
                                availableFolders.add(newFolder);
                                selectedFolderId = newFolder.id;
                                selectedFolderPath = newFolder.name;
                                _folderNameController.clear();
                              });
                            }
                          },
                          child: const Text('Crear carpeta'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _labelController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Ingresa el Nombre del Activo y/o Componente',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _coordsController,
                    decoration: const InputDecoration(
                      hintText:
                          'Agregar las Coordenadas del Activo y/o Componente',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _localityController,
                    decoration: const InputDecoration(
                      hintText: 'Localidad (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información de ubicación:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        widget.buildLocationInfoRow(
                          'Latitud:',
                          currentLat.toStringAsFixed(6),
                        ),
                        widget.buildLocationInfoRow(
                          'Longitud:',
                          currentLng.toStringAsFixed(6),
                        ),
                        widget.buildLocationInfoRow('UTM:', utmCoords),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              if (widget.drawingType == 'point' ||
                  widget.drawingType == 'line' ||
                  widget.drawingType == 'polygon') ...[
                // Solo mostrar para puntos (segun codigo original, pero la condicional incluye line y polygon)
                const SizedBox(height: 16),
                Row(
                  children: [
                    ...List.generate(photosTemp.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                photosTemp[index],
                                key: Key(photosTemp[index].path),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.error, color: Colors.red),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    photosTemp.removeAt(index);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (photosTemp.length < 3)
                      GestureDetector(
                        onTap: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.camera,
                            maxWidth: 800,
                            maxHeight: 800,
                          );

                          if (image != null) {
                            final File imageFile = File(image.path);

                            final utm = widget.getUTMCoordinates(
                              widget.centerPosition,
                            );
                            final altitud =
                                await ElevationService.fetchElevation(
                                  widget.centerPosition.latitude,
                                  widget.centerPosition.longitude,
                                );
                            final annotated = await widget.annotateImage(
                              imageFile,
                              _labelController.text,
                              utm,
                              altitud,
                            );

                            setState(() {
                              photosTemp.add(annotated);
                            });
                          }
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add_a_photo,
                            color: Colors.grey,
                            size: 32,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _observacionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Observación',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      final labelValue = _labelController.text.trim();
                      if (labelValue.isNotEmpty) {
                        widget.onSave(
                          LabelInputResult(
                            label: labelValue,
                            locality: _localityController.text.trim(),
                            coords: _coordsController.text.trim(),
                            observation: _observacionController.text.trim(),
                            selectedFolderId: selectedFolderId,
                            selectedFolderPath: selectedFolderPath,
                            photos: photosTemp,
                          ),
                        );
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
