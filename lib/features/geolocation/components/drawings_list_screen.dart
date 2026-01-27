import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:latlong2/latlong.dart';
import 'package:utm/utm.dart';

class DrawingsListScreen extends StatelessWidget {
  final List<SavedDrawingLayer> savedLayers;
  final void Function(List<LatLng>) onLayerFocus;

  const DrawingsListScreen({
    super.key,
    required this.savedLayers,
    required this.onLayerFocus,
  });

  @override
  Widget build(BuildContext context) {
    // Verificar si la lista está vacía
    if (savedLayers.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lista de Elementos'),
          backgroundColor: Colors.blueGrey[800],
          elevation: 2,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No hay elementos guardados',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea algunos dibujos en el mapa para verlos aquí',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Separar los elementos en diferentes listas
    final tracks = savedLayers
        .where((layer) => layer.name.toLowerCase().startsWith('saved_track'))
        .toList();
    final layers = savedLayers
        .where((layer) => !layer.name.toLowerCase().startsWith('saved_track'))
        .toList();
    // final drawings = layers
    //     .where((layer) => layer.name.toLowerCase().contains('dibujo'))
    //     .toList();
    final otherLayers = layers
        .where((layer) => !layer.name.toLowerCase().contains('dibujo'))
        .toList();

    // Agrupar dibujos por carpeta
    final Map<String?, List<SavedDrawingLayer>> dibujosPorCarpeta = {};

    // Organizar dibujos por carpeta usando folderId como clave
    for (var dibujo in otherLayers) {
      final folderId = dibujo.folderId ?? 'sin_carpeta';

      if (!dibujosPorCarpeta.containsKey(folderId)) {
        dibujosPorCarpeta[folderId] = [];
      }
      dibujosPorCarpeta[folderId]!.add(dibujo);
    }

    // Lista de secciones a mostrar
    final List<_Section> sections = [];

    // Agregar tracks
    if (tracks.isNotEmpty) {
      sections.add(_Section(title: 'Tracks', items: tracks));
    }

    // Crear un grupo para cada carpeta, primero 'sin_carpeta' y luego el resto ordenado alfabéticamente
    // Primero agregar "Sin carpeta" si existe
    if (dibujosPorCarpeta.containsKey('sin_carpeta')) {
      sections.add(_Section(
          title: 'Sin carpeta', items: dibujosPorCarpeta['sin_carpeta']!));
      dibujosPorCarpeta.remove('sin_carpeta');
    }

    // Ordenar el resto de carpetas alfabéticamente por nombre
    final carpetasOrdenadas = dibujosPorCarpeta.keys.toList()
      ..sort((a, b) {
        final nombreA =
            dibujosPorCarpeta[a]!.first.folderPath?.split('/').last ?? a ?? '';
        final nombreB =
            dibujosPorCarpeta[b]!.first.folderPath?.split('/').last ?? b ?? '';
        return nombreA.compareTo(nombreB);
      });

    // Agregar el resto de carpetas en orden
    for (var folderId in carpetasOrdenadas) {
      final folderName =
          dibujosPorCarpeta[folderId]!.first.folderPath?.split('/').last ??
              'Carpeta';
      sections.add(
          _Section(title: folderName, items: dibujosPorCarpeta[folderId]!));
    }

    // // Agregar otras capas
    // if (otherLayers.isNotEmpty) {
    //   sections.add(_Section(title: 'Otras Layers', items: otherLayers));
    // }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de elementos'),
        backgroundColor: Colors.blueGrey[800],
        elevation: 1,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Información',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Información de Dibujos'),
                  content: const Text(
                    'Aquí puedes ver todos tus dibujos guardados organizados por categorías. Los puntos pueden incluir fotos con coordenadas.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Entendido'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: sections.fold(
            0,
            (sum, section) =>
                sum! + section.items.length + 1), // +1 por el header
        itemBuilder: (context, index) {
          // Encontrar la sección correspondiente
          var currentIndex = 0;
          for (final section in sections) {
            if (index == currentIndex) {
              return _buildSectionHeader(
                  context, section.title, section.items.length);
            }
            currentIndex++;

            final itemIndex = index - currentIndex;
            if (itemIndex < section.items.length) {
              return _buildLayerCard(context, section.items[itemIndex]);
            }
            currentIndex += section.items.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getSectionIcon(title),
            size: 18,
            color: Colors.blueGrey[700],
          ),
          const SizedBox(width: 6),
          Text(
            '$title ($count)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[700],
                ),
          ),
        ],
      ),
    );
  }

  IconData _getSectionIcon(String title) {
    switch (title.toLowerCase()) {
      case 'tracks':
        return Icons.directions_run;
      case 'dibujos':
        return Icons.draw;
      case 'otras layers':
        return Icons.layers;
      default:
        return Icons.category;
    }
  }

  Widget _buildLayerCard(BuildContext context, SavedDrawingLayer layer) {
    final hasPoints = layer.points.isNotEmpty;
    final hasLines = layer.lines.isNotEmpty;
    final hasPolygons = layer.polygons.isNotEmpty;
    final totalElements =
        layer.points.length + layer.lines.length + layer.polygons.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: Colors.black26,
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getLayerIcon(layer),
            color: Colors.blueGrey[700],
            size: 20,
          ),
        ),
        title: Text(
          layer.name.replaceFirst(RegExp(r'saved_(track|layer)_'), ''),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creado: ${_formatTimestamp(layer.timestamp)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            if (totalElements > 0)
              Text(
                '$totalElements elemento${totalElements > 1 ? 's' : ''}',
                style: TextStyle(color: Colors.blueGrey[400], fontSize: 11),
              ),
          ],
        ),
        trailing: _buildLayerBadges(hasPoints, hasLines, hasPolygons),
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        children: [
          if (layer.points.isNotEmpty)
            ExpansionTile(
              title: Text('Puntos (${layer.points.length})'),
              children: layer.points.map((labeledMarker) {
                final point = labeledMarker.marker.point;
                final utm =
                    UTM.fromLatLon(lat: point.latitude, lon: point.longitude);

                final latText = 'Lat: ${point.latitude.toStringAsFixed(6)}';
                final lngText = 'Lng: ${point.longitude.toStringAsFixed(6)}';
                final utmText =
                    'UTM: ${utm.zone}  E: ${utm.easting.round()}  N: ${utm.northing.round()}';

                return StatefulBuilder(
                  builder: (context, setState) {
                    bool copied = false;

                    void copyToClipboard() async {
                      await Clipboard.setData(ClipboardData(
                        text: '$latText\n$lngText\n$utmText',
                      ));

                      setState(() => copied = true);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coordenadas copiadas')),
                      );

                      await Future.delayed(const Duration(seconds: 1));
                      setState(() => copied = false);
                    }

                    return Column(
                      children: [
                        ListTile(
                          leading:
                              const Icon(Icons.location_on, color: Colors.red),
                          title: Text(labeledMarker.label),
                          subtitle: layer.name.toLowerCase().contains('dibujo')
                              ? null
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(latText),
                                    Text(lngText),
                                    Text(utmText),
                                  ],
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.center_focus_strong,
                                    color: Colors.indigo),
                                tooltip: 'Enfocar en el mapa',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  onLayerFocus([point]);
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  copied ? Icons.check : Icons.copy,
                                  color: copied ? Colors.green : Colors.grey,
                                ),
                                onPressed: copyToClipboard,
                              ),
                            ],
                          ),
                        ),
                        _buildPhotosWidget(context, labeledMarker.photos),
                      ],
                    );
                  },
                );
              }).toList(),
            ),
          if (layer.lines.isNotEmpty)
            ExpansionTile(
              title: Text('Líneas (${layer.lines.length})'),
              children: layer.lines.map((line) {
                final polyline = line.polyline;
                final distance = _calculateDistance(polyline.points);
                final photos = _getAttributesPhotos(layer, 'photos_line');

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.timeline, color: Colors.blue),
                      title: Text('Línea: ${line.label}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Puntos: ${polyline.points.length}'),
                          Text('Grosor: ${polyline.strokeWidth}'),
                          Text('Distancia: ${_formatDistance(distance)}'),
                          Row(
                            children: [
                              const Text('Color: '),
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(
                                  color: polyline.color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _showPointsList(context, polyline.points),
                      trailing: IconButton(
                        icon: const Icon(Icons.center_focus_strong,
                            color: Colors.indigo),
                        tooltip: 'Enfocar en el mapa',
                        onPressed: () {
                          Navigator.of(context).pop();
                          onLayerFocus(polyline.points); // ✅ solo la línea
                        },
                      ),
                    ),
                    _buildPhotosWidget(context, photos),
                  ],
                );
              }).toList(),
            ),
          if (layer.polygons.isNotEmpty)
            ExpansionTile(
              title: Text('Polígonos (${layer.polygons.length})'),
              children: layer.polygons.map((polygon) {
                final area = _calculatePolygonArea(polygon.points);
                final photos = _getAttributesPhotos(layer, 'photos_polygon');

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.category, color: Colors.green),
                      title: const Text('Polígono'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Label: ${polygon.label}'),
                          Text('Vértices: ${polygon.points.length}'),
                          Text('Grosor de borde: ${polygon.borderStrokeWidth}'),
                          Text('Relleno: ${polygon.isFilled ? 'Sí' : 'No'}'),
                          Text('Área: ${_formatArea(area)}'),
                          Row(
                            children: [
                              const Text('Color: '),
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(
                                  color: polygon.color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _showPointsList(context, polygon.points),
                      trailing: IconButton(
                        icon: const Icon(Icons.center_focus_strong,
                            color: Colors.indigo),
                        tooltip: 'Enfocar en el mapa',
                        onPressed: () {
                          Navigator.of(context).pop();
                          onLayerFocus(polygon.points); // ✅ solo el polígono
                        },
                      ),
                    ),
                    _buildPhotosWidget(context, photos),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotosWidget(BuildContext context, List<File> photos) {
    if (photos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.photo_library, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Fotos (${photos.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _showPhotoDialog(context, photos[index]),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Image.file(
                          photos[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[100],
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image,
                                        size: 24, color: Colors.grey[400]),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Error',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${index + 1}/${photos.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<File> _getAttributesPhotos(SavedDrawingLayer layer, String key) {
    if (layer.attributes == null || !layer.attributes!.containsKey(key)) {
      return [];
    }
    final paths = layer.attributes![key];
    if (paths is List) {
      return paths.map((p) => File(p.toString())).toList();
    }
    return [];
  }

  IconData _getLayerIcon(SavedDrawingLayer layer) {
    if (layer.name.toLowerCase().contains('track')) {
      return Icons.directions_run;
    } else if (layer.name.toLowerCase().contains('dibujo')) {
      return Icons.draw;
    } else if (layer.points.isNotEmpty) {
      return Icons.location_on;
    } else if (layer.lines.isNotEmpty) {
      return Icons.timeline;
    } else if (layer.polygons.isNotEmpty) {
      return Icons.category;
    }
    return Icons.layers;
  }

  Widget _buildLayerBadges(bool hasPoints, bool hasLines, bool hasPolygons) {
    final badges = <Widget>[];

    if (hasPoints) {
      badges.add(_buildBadge(Icons.location_on, Colors.red));
    }
    if (hasLines) {
      badges.add(_buildBadge(Icons.timeline, Colors.blue));
    }
    if (hasPolygons) {
      badges.add(_buildBadge(Icons.category, Colors.green));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: badges,
    );
  }

  Widget _buildBadge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 10, color: color.withOpacity(0.8)),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d atrás';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h atrás';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m atrás';
    }
    return 'Ahora';
  }

  double _calculateDistance(List<LatLng> points) {
    if (points.length < 2) return 0;

    final Distance distance = Distance();
    double totalDistance = 0;

    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += distance.as(
        LengthUnit.Meter,
        points[i],
        points[i + 1],
      );
    }

    return totalDistance;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${meters.toStringAsFixed(2)} m | ${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(2)} m';
  }

  double _calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0;

    double area = 0;
    for (int i = 0; i < points.length - 1; i++) {
      area += (points[i].longitude * points[i + 1].latitude) -
          (points[i + 1].longitude * points[i].latitude);
    }

    area += (points.last.longitude * points.first.latitude) -
        (points.first.longitude * points.last.latitude);

    // Convertir a metros cuadrados (aproximación)
    area = (area.abs() / 2) * 111319.9 * 111319.9;
    return area;
  }

  String _formatArea(double squareMeters) {
    final hectares = squareMeters / 10000;
    return '${squareMeters.toStringAsFixed(2)} m² | ${hectares.toStringAsFixed(2)} ha';
  }

  void _showPointsList(BuildContext context, List<LatLng> points) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lista de Coordenadas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: points.map((point) {
              final utm =
                  UTM.fromLatLon(lat: point.latitude, lon: point.longitude);
              return ListTile(
                dense: true,
                title: Text(
                  'Lat: ${point.latitude.toStringAsFixed(6)}\n'
                  'Lng: ${point.longitude.toStringAsFixed(6)}\n'
                  'UTM: Zona ${utm.zone}  '
                  'E: ${utm.easting.round()}  '
                  'N: ${utm.northing.round()}',
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showPhotoDialog(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Stack(
            children: [
              InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(0),
                minScale: 0.1,
                maxScale: 4.0,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No se pudo cargar la imagen',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ruta: ${file.path}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    iconSize: 24,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Foto',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openPhotoViewer(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}

class _Section {
  final String title;
  final List<SavedDrawingLayer> items;

  _Section({required this.title, required this.items});
}
