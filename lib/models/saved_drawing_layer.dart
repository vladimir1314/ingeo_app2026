import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:latlong2/latlong.dart';

import 'geometry_data.dart';

class LabeledPolyline {
  final Polyline polyline;
  final String label;
  final String locality;
  final String manualCoordinates;
  final String observation;
  final List<String> photos;
  final Map<String, String> attributes;

  LabeledPolyline({
    required this.polyline,
    required this.label,
    this.locality = '',
    this.manualCoordinates = '',
    this.observation = '',
    this.photos = const [],
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'points': polyline.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'color': polyline.color.value,
      'strokeWidth': polyline.strokeWidth,
      'label': label,
      'locality': locality,
      'manualCoordinates': manualCoordinates,
      'observation': observation,
      'photos': photos,
      'attributes': attributes,
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
      locality: json['locality'] ?? '',
      manualCoordinates: json['manualCoordinates'] ?? '',
      observation: json['observation'] ?? '',
      photos: (json['photos'] as List?)?.cast<String>() ?? const [],
      attributes: (json['attributes'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    );
  }
}

class LabeledPolygon {
  final Polygon polygon;
  final String label;
  final String locality;
  final String manualCoordinates;
  final String observation;
  final List<String> photos;
  final Map<String, String> attributes;

  LabeledPolygon({
    required this.polygon,
    required this.label,
    this.locality = '',
    this.manualCoordinates = '',
    this.observation = '',
    this.photos = const [],
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'points': polygon.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'color': polygon.color.value,
      'borderStrokeWidth': polygon.borderStrokeWidth,
      'isFilled': polygon.isFilled,
      'label': label,
      'locality': locality,
      'manualCoordinates': manualCoordinates,
      'observation': observation,
      'photos': photos,
      'attributes': attributes,
    };
  }

  factory LabeledPolygon.fromJson(Map<String, dynamic> json) {
    return LabeledPolygon(
      polygon: Polygon(
        points: (json['points'] as List)
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList(),
        color: Color(json['color'] as int),
        borderStrokeWidth: (json['borderStrokeWidth'] as num?)?.toDouble() ?? 1.0,
        isFilled: json['isFilled'] ?? false,
        label: json['label'],
      ),
      label: json['label'] ?? '',
      locality: json['locality'] ?? '',
      manualCoordinates: json['manualCoordinates'] ?? '',
      observation: json['observation'] ?? '',
      photos: (json['photos'] as List?)?.cast<String>() ?? const [],
      attributes: (json['attributes'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    );
  }
}

class SavedDrawingLayer {
  final String id;
  final String name;

  final List<LabeledPolyline> lines;
  final List<LabeledPolygon> polygons;
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
      'polygons': polygons.map((polygon) => polygon.toJson()).toList(),
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
          .map((polygon) => LabeledPolygon.fromJson(polygon))
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
