import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geometry_data.dart';

class LabeledMarker {
  final Marker marker;
  final String label;
  final String locality;
  final String manualCoordinates;
  final String observation;
  final GeometryData geometry;
  final List<File> photos;
  final List<String> photoPaths;
  final Map<String, String> attributes;

  LabeledMarker({
    required this.marker,
    required this.label,
    this.locality = '',
    this.manualCoordinates = '',
    this.observation = '',
    required this.geometry,
    this.photos = const [],
    this.photoPaths = const [],
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'locality': locality,
    'manualCoordinates': manualCoordinates,
    'observation': observation,
    'geometry': geometry.toJson(),
    'point': {
      'lat': marker.point.latitude,
      'lng': marker.point.longitude,
    },
    'photoPaths': photoPaths.isNotEmpty ? photoPaths : photos.map((file) => file.path).toList(),
    'attributes': attributes,
  };

  factory LabeledMarker.fromJson(Map<String, dynamic> json) {
    final point = LatLng(json['point']['lat'], json['point']['lng']);
    final label = json['label'];
    final locality = json['locality'] ?? '';
    final manualCoordinates = json['manualCoordinates'] ?? '';
    final observation = json['observation'] ?? '';
    final geometry = GeometryData.fromJson(json['geometry']);
    final paths = (json['photoPaths'] as List?)?.cast<String>() ?? const [];
    final attributes = (json['attributes'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {};

    return LabeledMarker(
      label: label,
      locality: locality,
      manualCoordinates: manualCoordinates,
      observation: observation,
      geometry: geometry,
      marker: Marker(
        point: point,
        width: 40,
        height: 60,
        child: Builder(
          builder: (context) => GestureDetector(
            onTap: () => showGeometrySheet(context, geometry),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    label.split('\n').first,
                    style: const TextStyle(fontSize: 10, color: Colors.purple),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const Icon(Icons.place, color: Colors.red),
              ],
            ),
          ),
        ),
      ),
      photos: paths.map((p) => File(p)).toList(),
      photoPaths: paths,
      attributes: attributes,
    );
  }
}
