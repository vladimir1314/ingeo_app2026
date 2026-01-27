import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:latlong2/latlong.dart';

import 'geometry_data.dart';

class LabeledPolyline {
  final Polyline polyline;
  final String label;

  LabeledPolyline({required this.polyline, required this.label});

  Map<String, dynamic> toJson() {
    return {
      'points': polyline.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'color': polyline.color.value,
      'strokeWidth': polyline.strokeWidth,
      'label': label,
    };
  }

  factory LabeledPolyline.fromJson(Map<String, dynamic> json) {
    return LabeledPolyline(
      polyline: Polyline(
        points: (json['points'] as List)
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList(),
        color: Color(json['color'] as int),
        strokeWidth: json['strokeWidth'].toDouble(),
      ),
      label: json['label'] ?? '',
    );
  }
}

class SavedDrawingLayer {
  final String id;
  final String name;

  // final List<Polyline> lines;
  final List<LabeledPolyline> lines;
  final List<Polygon> polygons;
  // final List<Marker> points;
  final List<LabeledMarker> points;
  final DateTime timestamp;
  final List<GeometryData> rawGeometries;

  final Map<String, dynamic>? attributes; // Nueva propiedad
  final String? folderId; // ID de la carpeta a la que pertenece esta capa
  final String? folderPath; // Ruta completa de carpetas separadas por '/'

  SavedDrawingLayer({
    required this.id,
    required this.name,
    required this.points,
    required this.lines,
    required this.polygons,
    required this.rawGeometries,
    required this.timestamp,
    this.attributes, // Agregar parámetro opcional
    this.folderId, // ID de la carpeta contenedora
    this.folderPath, // Ruta completa de carpetas
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'timestamp': timestamp.toIso8601String(),
      'lines': lines.map((line) => line.toJson()).toList(),
      'polygons': polygons
          .map((polygon) => {
                'points': polygon.points
                    .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                    .toList(),
                'color': polygon.color.value,
                'borderStrokeWidth': polygon.borderStrokeWidth,
                'isFilled': polygon.isFilled,
                'label': polygon.label,
              })
          .toList(),
      'points': points.map((labeledMarker) => labeledMarker.toJson()).toList(),
      'rawGeometries': rawGeometries.map((g) => g.toJson()).toList(),
      'folderId': folderId,
      'folderPath': folderPath,
      'attributes': attributes,
    };
  }

  factory SavedDrawingLayer.fromJson(Map<String, dynamic> json) {
    return SavedDrawingLayer(
      id: json['id'],
      name: json['name'],
      timestamp: DateTime.parse(json['timestamp']),
      lines: (json['lines'] as List)
          .map((line) => LabeledPolyline.fromJson(line))
          .toList(),
      polygons: (json['polygons'] as List)
          .map((polygon) => Polygon(
                points: (polygon['points'] as List)
                    .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
                    .toList(),
                color: Color(polygon['color'] as int),
                borderStrokeWidth: polygon['borderStrokeWidth'] as double,
                isFilled: polygon['isFilled'] as bool,
                label: polygon['label'],
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: Colors.black,
                  fontWeight: FontWeight.w400,
                  backgroundColor: Color.fromRGBO(
                      255, 255, 255, 0.7), // fondo blanco translúcido
                  shadows: [
                    Shadow(
                      color: Color.fromRGBO(0, 0, 0, 0.2), // sombra sutil
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                labelPlacement: PolygonLabelPlacement.centroid,
                rotateLabel: false,
              ))
          .toList(),
      points: (json['points'] as List)
          .map((p) => LabeledMarker.fromJson(p))
          .toList(),
      rawGeometries: (json['rawGeometries'] as List)
          .map((g) => GeometryData.fromJson(g))
          .toList(),
      folderId: json['folderId'],
      folderPath: json['folderPath'],
      attributes: json['attributes'] as Map<String, dynamic>?,
    );
  }
}
