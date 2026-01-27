import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geometry_data.dart';

class LabeledMarker {
  final Marker marker;
  final String label;
  final GeometryData geometry;
  final List<File> photos;
  final List<String> photoPaths;

  LabeledMarker({
    required this.marker,
    required this.label,
    required this.geometry,
    this.photos = const [],
    this.photoPaths = const [],
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'geometry': geometry.toJson(),
    'point': {
      'lat': marker.point.latitude,
      'lng': marker.point.longitude,
    },
    'photoPaths': photoPaths.isNotEmpty ? photoPaths : photos.map((file) => file.path).toList(),
  };

  factory LabeledMarker.fromJson(Map<String, dynamic> json) {
    final point = LatLng(json['point']['lat'], json['point']['lng']);
    final label = json['label'];
    final geometry = GeometryData.fromJson(json['geometry']);
    final paths = (json['photoPaths'] as List?)?.cast<String>() ?? const [];

    return LabeledMarker(
      label: label,
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
    );
  }
}
