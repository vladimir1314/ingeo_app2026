import 'package:flutter/material.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';

class DrawingsLayerSelector extends StatefulWidget {
  final List<SavedDrawingLayer> savedLayers;
  final Function(String, bool) onLayerToggle;
  final void Function(Map<String, List<SavedDrawingLayer>> layersByFolder,
      String format, String? fileName)? onExport;

  const DrawingsLayerSelector({
    super.key,
    required this.savedLayers,
    required this.onLayerToggle,
    this.onExport,
  });

  @override
  State<DrawingsLayerSelector> createState() => _DrawingsLayerSelectorState();
}

class _DrawingsLayerSelectorState extends State<DrawingsLayerSelector> {
  Map<String, bool> layerStates = {};
  Map<String, bool> folderStates = {};
  String exportFormat = 'kml';
  String exportFileName = '';
  bool exportByFolder = true;

  @override
  void initState() {
    super.initState();
    for (var layer in widget.savedLayers) {
      layerStates[layer.id] = true;
    }
    _initializeFolderStates();
  }

  void _initializeFolderStates() {
    final folders = _getLayersByFolder().keys;
    for (var folder in folders) {
      folderStates[folder] = true;
    }
  }

  Map<String, List<SavedDrawingLayer>> _getLayersByFolder() {
    final Map<String, List<SavedDrawingLayer>> layersByFolder = {};

    for (var layer in widget.savedLayers) {
      final folderKey = layer.folderId ?? 'sin_carpeta';
      final folderName = layer.folderPath ?? 'Sin carpeta';

      if (!layersByFolder.containsKey(folderKey)) {
        layersByFolder[folderKey] = [];
      }
      layersByFolder[folderKey]!.add(layer);
    }

    return layersByFolder;
  }

  String _getFolderDisplayName(
      String folderKey, List<SavedDrawingLayer> layers) {
    if (folderKey == 'sin_carpeta') return 'Sin carpeta';
    return layers.first.folderPath ?? 'Carpeta';
  }

  @override
  Widget build(BuildContext context) {
    final layersByFolder = _getLayersByFolder();

    return Material(
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal.shade50,
              Colors.white,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(-5, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header mejorado
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade600, Colors.teal.shade400],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.file_download,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Exportar Capas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.savedLayers.length} capas disponibles',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Opción de exportación por carpeta
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.blue.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Exportar por carpetas',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Crear archivos separados por cada carpeta',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: exportByFolder,
                    onChanged: (value) {
                      setState(() {
                        exportByFolder = value;
                      });
                    },
                    activeColor: Colors.blue.shade600,
                  ),
                ],
              ),
            ),

            // Lista de carpetas y capas
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: layersByFolder.length,
                itemBuilder: (context, index) {
                  final folderKey = layersByFolder.keys.elementAt(index);
                  final layers = layersByFolder[folderKey]!;
                  final folderName = _getFolderDisplayName(folderKey, layers);
                  final isExpanded = folderStates[folderKey] ?? true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Header de carpeta
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.grey.shade100,
                                Colors.grey.shade50
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              folderKey == 'sin_carpeta'
                                  ? Icons.folder_open
                                  : Icons.folder,
                              color: Colors.amber.shade700,
                            ),
                            title: Text(
                              folderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              '${layers.length} capa${layers.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: layers.every(
                                      (layer) => layerStates[layer.id] == true),
                                  tristate: true,
                                  onChanged: (value) {
                                    setState(() {
                                      for (var layer in layers) {
                                        layerStates[layer.id] = value ?? false;
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      folderStates[folderKey] = !isExpanded;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Capas de la carpeta
                        if (isExpanded)
                          ...layers
                              .map((layer) => Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                            color: Colors.grey.shade200),
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.only(
                                          left: 60, right: 16),
                                      title: Text(
                                        layer.name,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      subtitle: _buildLayerInfo(layer),
                                      trailing: Checkbox(
                                        value: layerStates[layer.id] ?? false,
                                        onChanged: (bool? value) {
                                          if (value != null) {
                                            setState(() {
                                              layerStates[layer.id] = value;
                                            });
                                            widget.onLayerToggle(
                                                layer.id, value);
                                          }
                                        },
                                      ),
                                    ),
                                  ))
                              .toList(),
                      ],
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Panel de exportación mejorado
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Campo de nombre de archivo
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: exportByFolder
                            ? 'Prefijo de archivos'
                            : 'Nombre del archivo',
                        hintText: exportByFolder
                            ? 'Ej: exportacion (se añadirá _carpeta.kml)'
                            : 'Dejar vacío para nombre automático',
                        prefixIcon: const Icon(Icons.edit),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      onChanged: (value) {
                        setState(() {
                          exportFileName = value.trim();
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Selector de formato
                  Row(
                    children: [
                      const Icon(Icons.file_present, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text(
                        'Formato:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('KML'),
                                selected: exportFormat == 'kml',
                                onSelected: (_) {
                                  setState(() => exportFormat = 'kml');
                                },
                                selectedColor: Colors.teal.shade100,
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('KMZ'),
                                selected: exportFormat == 'kmz',
                                onSelected: (_) {
                                  setState(() => exportFormat = 'kmz');
                                },
                                selectedColor: Colors.teal.shade100,
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Botón de exportación
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade600, Colors.teal.shade400],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: Text(
                        exportByFolder
                            ? 'Exportar por Carpetas'
                            : 'Exportar Seleccionados',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        final selectedLayers = widget.savedLayers
                            .where((layer) => layerStates[layer.id] == true)
                            .toList();

                        if (selectedLayers.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.warning, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('No hay capas seleccionadas'),
                                ],
                              ),
                              backgroundColor: Colors.orange.shade600,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        Navigator.of(context).pop();

                        if (widget.onExport != null) {
                          if (exportByFolder) {
                            // Agrupar capas seleccionadas por carpeta (por nombre)
                            final Map<String, List<SavedDrawingLayer>>
                                selectedByFolder = {};
                            for (var layer in selectedLayers) {
                              final folderKey =
                                  layer.folderPath ?? 'Capas_Externas';
                              if (!selectedByFolder.containsKey(folderKey)) {
                                selectedByFolder[folderKey] = [];
                              }
                              selectedByFolder[folderKey]!.add(layer);
                            }
                            widget.onExport!(
                                selectedByFolder,
                                exportFormat,
                                exportFileName.isNotEmpty
                                    ? exportFileName
                                    : null);
                          } else {
                            // Exportar todo junto
                            final allInOne = {
                              'todas_las_capas': selectedLayers
                            };
                            widget.onExport!(
                                allInOne,
                                exportFormat,
                                exportFileName.isNotEmpty
                                    ? exportFileName
                                    : null);
                          }
                        }
                      },
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

  Widget _buildLayerInfo(SavedDrawingLayer layer) {
    List<String> details = [];
    if (layer.points.isNotEmpty) details.add('${layer.points.length} puntos');
    if (layer.lines.isNotEmpty) details.add('${layer.lines.length} líneas');
    if (layer.polygons.isNotEmpty)
      details.add('${layer.polygons.length} polígonos');

    return Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          details.join(', '),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
