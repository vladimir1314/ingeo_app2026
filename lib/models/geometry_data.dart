import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class GeometryData {
  final String type;
  final String name;
  final List<LatLng> coordinates;
  final String? styleUrl;

  GeometryData({
    required this.type,
    required this.name,
    required this.coordinates,
    this.styleUrl,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'coordinates': coordinates
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'styleUrl': styleUrl,
      };

  static GeometryData fromJson(Map<String, dynamic> json) => GeometryData(
        type: json['type'],
        name: json['name'],
        coordinates: (json['coordinates'] as List)
            .map((p) => LatLng(p['lat'], p['lng']))
            .toList(),
        styleUrl: json['styleUrl'],
      );
}

void showGeometrySheet(BuildContext context, GeometryData data) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.4,
        maxChildSize: 0.7,
        minChildSize: 0.2,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: controller,
            children: [
              Text(
                data.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text("Tipo: ${data.type}"),
              if (data.styleUrl != null) Text("Estilo: ${data.styleUrl}"),
              const SizedBox(height: 8),
              const Text("Coordenadas:"),
              ...data.coordinates.map((c) => Text(
                    "• ${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(fontFamily: 'monospace'),
                  )),
            ],
          ),
        ),
      );
    },
  );
}
