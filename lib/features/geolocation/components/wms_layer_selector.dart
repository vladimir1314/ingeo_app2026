import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/models/wms_layer.dart';
import 'package:ingeo_app/features/geolocation/components/drawings_list_screen.dart';
import 'package:ingeo_app/utils/wms_capabilities.dart';
import 'package:ingeo_app/utils/wms_layer_info.dart';
import 'package:latlong2/latlong.dart';

class _LayerItem {
  final String title;
  final String layerId;
  final Function(bool)? onToggle;
  final Function()? onDelete;
  final String? legendUrl;
  final double? legendWidth;
  final double? legendHeight;

  _LayerItem(
    this.title,
    this.layerId, {
    this.onToggle,
    this.onDelete,
    this.legendUrl,
    this.legendWidth,
    this.legendHeight,
  });
}

class WmsLayerSelector extends StatelessWidget {
  final Map<String, bool> layerStates;
  final Function(String, bool) onLayerToggle;
  final Function(String) onLayerDelete;
  final VoidCallback onClose;
  final List<SavedDrawingLayer> savedLayers;
  final Function(String) onLayerFocus;
  final MapController mapController;
  final Function(Map<String, dynamic>)? onWmsLayerAdd;
  final List<WmsLayer> wmsLayers;
  final List<LayerGroup>? customLayerGroups;

  const WmsLayerSelector({
    super.key,
    required this.layerStates,
    required this.onLayerToggle,
    required this.onClose,
    required this.savedLayers,
    required this.onLayerDelete,
    required this.onLayerFocus,
    required this.mapController,
    this.onWmsLayerAdd,
    this.wmsLayers = const [],
    this.customLayerGroups,
  });

  void handleLayerFocus(List<LatLng> focusPoints) {
    if (focusPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(focusPoints);
    mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(32)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4, // Reduced height
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with drag handle
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Text(
                        'Capas Temáticas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Layer list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // Encabezado general de Dibujos con botón de lista
                if (layerStates.keys.any(
                  (key) => key.startsWith('saved_layer_'),
                )) ...[
                  _buildLayerGroup(context, 'Dibujos', []),
                  ..._buildDrawingsByFolder(context),
                ],
                if (layerStates.keys.any(
                  (key) => key.startsWith('external_layer_'),
                ))
                  _buildLayerGroup(
                    context,
                    'Capas externas',
                    layerStates.entries
                        .where(
                          (entry) => entry.key.startsWith('external_layer_'),
                        )
                        .map((entry) {
                          final layerIndex = savedLayers.indexWhere(
                            (layer) => layer.id == entry.key,
                          );
                          if (layerIndex >= 0) {
                            return _LayerItem(
                              savedLayers[layerIndex].name,
                              entry.key,
                            );
                          }
                          return null;
                        })
                        .whereType<_LayerItem>()
                        .toList(),
                  ),
                if (layerStates.keys.any(
                  (key) => key.startsWith('saved_track_'),
                ))
                  _buildLayerGroup(
                    context,
                    'Track',
                    layerStates.entries
                        .where((entry) => entry.key.startsWith('saved_track_'))
                        .map((entry) {
                          final layerIndex = savedLayers.indexWhere(
                            (layer) => layer.id == entry.key,
                          );
                          if (layerIndex >= 0) {
                            return _LayerItem(
                              savedLayers[layerIndex].name,
                              entry.key,
                            );
                          }
                          return null;
                        })
                        .whereType<_LayerItem>()
                        .toList(),
                  ),
                if (layerStates.keys.any(
                  (key) => key.startsWith('intersection_'),
                ))
                  _buildLayerGroup(
                    context,
                    'Intersección',
                    layerStates.entries
                        .where((entry) => entry.key.startsWith('intersection_'))
                        .map((entry) {
                          final layerIndex = savedLayers.indexWhere(
                            (layer) => layer.id == entry.key,
                          );
                          if (layerIndex >= 0) {
                            return _LayerItem(
                              savedLayers[layerIndex].name,
                              entry.key,
                            );
                          }
                          return null;
                        })
                        .whereType<_LayerItem>()
                        .toList(),
                  ),
                // Modificar la sección que construye las capas WMS
                // if (layerStates.keys.any((key) => key.startsWith('wms_layer_')))
                // Modificar la sección que construye las capas WMS
                _buildLayerGroup(
                  context,
                  'Capas WMS',
                  wmsLayers.map((layer) {
                    final uri = Uri.parse(layer.url);
                    final legendUri = uri.replace(
                      queryParameters: {
                        'SERVICE': 'WMS',
                        'VERSION': '1.3.0',
                        'REQUEST': 'GetLegendGraphic',
                        'FORMAT': 'image/png',
                        'LAYER': layer.layerName,
                        'RULE': '', // vacío = primera regla
                        'WIDTH': '20',
                        'HEIGHT': '20',
                        'TRANSPARENT': 'true',
                        'LEGEND_OPTIONS':
                            'forceLabels:off;fontSize:11;fontName:Arial;fontAntiAliasing:true',
                      },
                    );

                    debugPrint(
                      'WMS layer legend URL: ${legendUri.toString()}',
                    ); // Debug

                    return _LayerItem(
                      layer.name,
                      layer.id,
                      onToggle: (value) => onLayerToggle(layer.id, value),
                      onDelete: () => onLayerDelete(layer.id),
                      legendUrl: legendUri.toString(),
                    );
                  }).toList(),
                ),
                if (customLayerGroups != null)
                  ...customLayerGroups!.map(
                    (group) => _buildLayerGroup(
                      context,
                      group.title,
                      group.items.map((item) {
                        final baseUrl =
                            'https://geoserver140.ideasg.org/geoserver/ingeo/wms';

                        final legendUri = Uri.parse(baseUrl).replace(
                          queryParameters: {
                            'SERVICE': 'WMS',
                            'VERSION': '1.3.0',
                            'REQUEST': 'GetLegendGraphic',
                            'FORMAT': 'image/png',
                            'LAYER': 'ingeo:${item.layerId}',
                            'RULE': '', // vacío = primera regla
                            'WIDTH': '20',
                            'HEIGHT': '20',
                            'TRANSPARENT': 'true',
                            'LEGEND_OPTIONS':
                                'forceLabels:on;fontSize:11;fontName:Arial;fontAntiAliasing:true',
                          },
                        );

                        debugPrint(
                          'Custom layer legend URL: ${legendUri.toString()}',
                        ); // Debug

                        return _LayerItem(
                          item.title,
                          item.layerId,
                          legendUrl: legendUri.toString(),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDrawingsByFolder(BuildContext context) {
    // Agrupar dibujos por carpeta
    final Map<String?, List<SavedDrawingLayer>> drawingsByFolder = {};

    // Obtener las capas de dibujo
    final drawingLayers = savedLayers
        .where(
          (layer) =>
              layerStates.keys.contains(layer.id) &&
              layer.id.startsWith('saved_layer_'),
        )
        .toList();

    // Agrupar por carpeta
    for (var layer in drawingLayers) {
      final folderId = layer.folderId ?? 'sin_carpeta';
      if (!drawingsByFolder.containsKey(folderId)) {
        drawingsByFolder[folderId] = [];
      }
      drawingsByFolder[folderId]!.add(layer);
    }

    // Lista para almacenar los widgets resultantes
    List<Widget> folderGroups = [];

    // Crear un grupo para cada carpeta
    drawingsByFolder.forEach((folderId, layers) {
      final folderName = folderId == 'sin_carpeta'
          ? 'Sin carpeta'
          : layers.first.folderPath ?? 'Carpeta';

      folderGroups.add(
        _buildLayerGroup(
          context,
          'Dibujos: $folderName',
          layers.map((layer) {
            return _LayerItem(layer.name, layer.id);
          }).toList(),
        ),
      );
    });

    return folderGroups;
  }

  Widget _buildLayerGroup(
    BuildContext context,
    String title,
    List<_LayerItem> items,
  ) {
    // Logic for "Dibujos" checkbox (afecta solo los items del grupo)
    bool? groupCheckboxValue;
    VoidCallback? onGroupToggle;

    if (title.startsWith('Dibujos')) {
      final drawingKeys = items.map((i) => i.layerId).toList();

      if (drawingKeys.isNotEmpty) {
        final allChecked = drawingKeys.every((k) => layerStates[k] == true);
        final noneChecked = drawingKeys.every((k) => layerStates[k] != true);

        if (allChecked) {
          groupCheckboxValue = true;
        } else if (noneChecked) {
          groupCheckboxValue = false;
        } else {
          groupCheckboxValue = null; // Tristate
        }

        onGroupToggle = () {
          final bool targetState = groupCheckboxValue != true;
          for (final key in drawingKeys) {
            if ((layerStates[key] ?? false) != targetState) {
              onLayerToggle(key, targetState);
            }
          }
        };
      }
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (title.startsWith('Dibujos') && onGroupToggle != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: groupCheckboxValue,
                          tristate: true,
                          onChanged: (_) => onGroupToggle!(),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF37474F),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              if (title == 'Dibujos' || title == 'Capas externas')
                IconButton(
                  icon: const Icon(Icons.list, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DrawingsListScreen(
                          savedLayers: savedLayers,
                          onLayerFocus: handleLayerFocus,
                        ),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              if (title == 'Capas WMS')
                IconButton(
                  icon: const Icon(Icons.add),
                  color: Colors.green[900],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) =>
                          WmsLayerModal(onWmsLayerAdd: onWmsLayerAdd),
                    );
                  },
                ),
            ],
          ),
        ),
        children: [
          if (items.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: items.map((item) => _buildLayerItem(item)).toList(),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLayerItem(_LayerItem item) {
    final title = item.title;
    final layerId = item.layerId;
    final isDrawingLayer = layerId.startsWith('saved_layer_');
    final isTrackLayer = layerId.startsWith('saved_track_');
    final isExternalLayer = layerId.startsWith('external_layer_');
    final isIntersectionLayer = layerId.startsWith('intersection_');
    final isWmsLayer = layerId.startsWith('wms_layer_');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onLayerToggle(layerId, !(layerStates[layerId] ?? false)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: layerStates[layerId] ?? false,
                      onChanged: (value) =>
                          onLayerToggle(layerId, value ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isDrawingLayer ||
                      isTrackLayer ||
                      isExternalLayer ||
                      isIntersectionLayer) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.center_focus_strong,
                        size: 20,
                        color: Colors.blue,
                      ),
                      onPressed: () => onLayerFocus(layerId),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        size: 20,
                        color: Colors.red,
                      ),
                      onPressed: () => onLayerDelete(layerId),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (isWmsLayer)
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        size: 20,
                        color: Colors.red,
                      ),
                      onPressed: () => onLayerDelete(layerId),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (item.legendUrl != null)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 4, bottom: 4),
                  child: Image.network(
                    item.legendUrl!,
                    width: item.legendWidth,
                    height: item.legendHeight,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Image load error: $error');
                      return const SizedBox.shrink();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WmsLayerModal extends StatefulWidget {
  final Function(Map<String, dynamic>)? onWmsLayerAdd;

  const WmsLayerModal({super.key, this.onWmsLayerAdd});

  @override
  State<WmsLayerModal> createState() => _WmsLayerModalState();
}

class _WmsLayerModalState extends State<WmsLayerModal> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _layerNameController = TextEditingController();
  final _layerTitleController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingLayers = false;
  List<WmsLayerInfo> _availableLayers = [];
  WmsLayerInfo? _selectedLayer;

  @override
  void dispose() {
    _urlController.dispose();
    _layerNameController.dispose();
    _layerTitleController.dispose();
    super.dispose();
  }

  Future<void> _handleAddLayer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final wmsLayer = {
        'url': _urlController.text.trim(),
        'name': _layerNameController.text.trim(),
        'title': _layerTitleController.text.trim(),
        'id': 'wms_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'wms_layer',
      };

      widget.onWmsLayerAdd?.call(wmsLayer);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al agregar capa WMS: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets, // ← Ajuste por teclado
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ← Permite altura dinámica
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Crear una nueva conexión WMS​',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'URL del servicio WMS',
                          hintText: 'https://ejemplo.com/wms',
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'La URL es requerida';
                          }
                          if (!Uri.tryParse(value!)!.isAbsolute) {
                            return 'URL inválida';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          setState(() => _isLoadingLayers = true);
                          try {
                            final url = _urlController.text.trim();
                            _availableLayers = await fetchWmsLayersFromUrl(url);
                            if (_availableLayers.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No se encontraron capas'),
                                ),
                              );
                            } else {
                              setState(
                                () => _selectedLayer = _availableLayers.first,
                              );
                              _layerNameController.text = _selectedLayer!.name;
                              _layerTitleController.text =
                                  _selectedLayer!.title;
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al cargar capas: $e'),
                              ),
                            );
                          } finally {
                            setState(() => _isLoadingLayers = false);
                          }
                        },
                        child: _isLoadingLayers
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Cargar Capas temáticas disponibles'),
                      ),
                      if (_availableLayers.isNotEmpty)
                        DropdownButton<WmsLayerInfo>(
                          value: _selectedLayer,
                          onChanged: (WmsLayerInfo? newLayer) {
                            setState(() {
                              _selectedLayer = newLayer;
                              _layerNameController.text = newLayer!.name;
                              _layerTitleController.text = newLayer.title;
                            });
                          },
                          items: _availableLayers.map((layer) {
                            return DropdownMenuItem(
                              value: layer,
                              child: Text(layer.title),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _layerTitleController,
                        decoration: const InputDecoration(
                          labelText: 'Capa temática Seleccionada',
                          hintText: 'Mi Capa WMS',
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'El título es requerido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleAddLayer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.teal, // Color de fondo del botón
                          foregroundColor:
                              Colors.white, // Color del texto e iconos
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors
                                      .white, // Color del indicador de carga
                                ),
                              )
                            : const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
