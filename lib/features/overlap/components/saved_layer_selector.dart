import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:latlong2/latlong.dart';

class _LayerItem {
  final String title;
  final String layerId;
  final Function(bool)? onToggle;
  final Function()? onDelete;

  _LayerItem(this.title, this.layerId, {this.onToggle, this.onDelete});
}

class SavedLayerSelector extends StatelessWidget {
  final Map<String, bool> layerStates;
  final Function(String, bool) onLayerToggle;
  final Function(String) onLayerDelete;
  final VoidCallback onClose;
  final List<SavedDrawingLayer> savedLayers;
  final Function(String) onLayerFocus;
  final MapController mapController;

  const SavedLayerSelector({
    super.key,
    required this.layerStates,
    required this.onLayerToggle,
    required this.onClose,
    required this.savedLayers,
    required this.onLayerDelete,
    required this.onLayerFocus,
    required this.mapController,
  });

  void handleLayerFocus(List<LatLng> focusPoints) {
    if (focusPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(focusPoints);
    mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(32)),
    );
  }

  Widget _buildLayerGroup(
    BuildContext context,
    String title,
    List<_LayerItem> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
        ...items.map((item) => _buildLayerTile(context, item)),
      ],
    );
  }

  Widget _buildLayerTile(BuildContext context, _LayerItem item) {
    final layer = savedLayers.firstWhere((layer) => layer.id == item.layerId);
    final isActive = layerStates[item.layerId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        title: Text(item.title, style: const TextStyle(fontSize: 14)),
        leading: Checkbox(
          value: isActive,
          onChanged: (value) {
            if (value != null) {
              onLayerToggle(item.layerId, value);
            }
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.center_focus_strong, size: 20),
              onPressed: () {
                List<LatLng> focusPoints = [];
                focusPoints.addAll(layer.points.map((p) => p.marker.point));
                focusPoints.addAll(
                  layer.lines.expand((line) => line.polyline.points),
                );
                focusPoints.addAll(
                  layer.polygons.expand((polygon) => polygon.polygon.points),
                );
                handleLayerFocus(focusPoints);
                onLayerFocus(item.layerId);
              },
            ),
            // IconButton(
            //   icon: const Icon(Icons.delete_outline, size: 20),
            //   onPressed: () => onLayerDelete(item.layerId),
            // ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
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
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
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
                        'Capas de Dibujo',
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildLayerGroup(
                  context,
                  'Dibujos',
                  layerStates.entries
                      .where((entry) => entry.key.startsWith('saved_layer_'))
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
                _buildLayerGroup(context, 'Grilla', [
                  _LayerItem('UTM Peru', 'sp_grilla_utm_peru'),
                ]),
                _buildLayerGroup(context, 'Comunidades', [
                  _LayerItem(
                    'Comunidades Campesinas',
                    'sp_comunidades_campesinas',
                  ),
                  _LayerItem('Comunidades Nativas', 'sp_comunidades_nativas'),
                ]),
                _buildLayerGroup(context, 'División Política', [
                  _LayerItem('Departamentos', 'sp_departamentos'),
                  _LayerItem('Provincias', 'sp_provincias'),
                  _LayerItem('Distritos', 'sp_distritos'),
                ]),
                _buildLayerGroup(context, 'Sub-cuencas', [
                  _LayerItem('Cuencas', 'sp_cuencas'),
                  _LayerItem('Subcuencas', 'sp_subcuencas'),
                ]),
                _buildLayerGroup(context, 'Lagunas', [
                  _LayerItem('Lagunas', 'sp_lagunas'),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
