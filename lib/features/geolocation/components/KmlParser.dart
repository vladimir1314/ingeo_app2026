import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

/// Modelo para estilos
class KmlStyle {
  final String id;
  final String? iconHref;
  final double? iconScale;
  final Color? labelColor;
  final double? labelScale;
  final Color? lineColor;
  final double? lineWidth;
  final Color? polyColor;

  KmlStyle({
    required this.id,
    this.iconHref,
    this.iconScale,
    this.labelColor,
    this.labelScale,
    this.lineColor,
    this.lineWidth,
    this.polyColor,
  });
}

/// Parser principal de KML
class KmlParser {
  final XmlDocument xml;
  final Map<String, KmlStyle> styles = {};

  KmlParser(this.xml);

  static Future<KmlParser> fromFile(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    final xml = XmlDocument.parse(content);
    return KmlParser(xml).._parseStyles();
  }

  List<GeometryData> parseAllGeometries() {
    final geometries = <GeometryData>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final name = pm.getElement('name')?.text ?? '';
      final styleUrl = pm.getElement('styleUrl')?.text;

      final pointElem = pm.findAllElements('Point').firstOrNull;
      final lineElem = pm.findAllElements('LineString').firstOrNull;
      final polyElem = pm.findAllElements('Polygon').firstOrNull;

      if (pointElem != null) {
        final coordText =
            pointElem.findAllElements('coordinates').firstOrNull?.text;
        final parts = coordText?.trim().split(',') ?? [];
        if (parts.length >= 2) {
          final lon = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          if (lat != null && lon != null) {
            geometries.add(GeometryData(
              type: 'Point',
              name: name,
              coordinates: [LatLng(lat, lon)],
              styleUrl: styleUrl,
            ));
          }
        }
      }

      if (lineElem != null) {
        final coordText =
            lineElem.findElements('coordinates').firstOrNull?.text;
        if (coordText != null) {
          final coords = coordText
              .trim()
              .split(RegExp(r'\s+'))
              .map((c) {
                final parts = c.split(',');
                if (parts.length < 2) return null;
                final lon = double.tryParse(parts[0]);
                final lat = double.tryParse(parts[1]);
                if (lat == null || lon == null) return null;
                return LatLng(lat, lon);
              })
              .whereType<LatLng>()
              .toList();
          if (coords.isNotEmpty) {
            geometries.add(GeometryData(
              type: 'LineString',
              name: name,
              coordinates: coords,
              styleUrl: styleUrl,
            ));
          }
        }
      }

      if (polyElem != null) {
        final coordText = polyElem
            .findAllElements('outerBoundaryIs')
            .expand((e) => e.findElements('LinearRing'))
            .expand((e) => e.findElements('coordinates'))
            .map((e) => e.text)
            .firstOrNull;

        if (coordText != null) {
          final coords = coordText
              .trim()
              .split(RegExp(r'\s+'))
              .map((c) {
                final parts = c.split(',');
                if (parts.length < 2) return null;
                final lon = double.tryParse(parts[0]);
                final lat = double.tryParse(parts[1]);
                if (lat == null || lon == null) return null;
                return LatLng(lat, lon);
              })
              .whereType<LatLng>()
              .toList();

          if (coords.isNotEmpty) {
            geometries.add(GeometryData(
              type: 'Polygon',
              name: name,
              coordinates: coords,
              styleUrl: styleUrl,
            ));
          }
        }
      }
    }

    return geometries;
  }

  void _parseStyles() {
    for (final styleElem in xml.findAllElements('Style')) {
      final id = styleElem.getAttribute('id') ?? '';
      final iconHref = styleElem
          .findAllElements('Icon')
          .expand((e) => e.findElements('href'))
          .map((e) => e.text)
          .firstOrNull;

      final iconScale = styleElem
          .findAllElements('IconStyle')
          .expand((e) => e.findElements('scale'))
          .map((e) => double.tryParse(e.text))
          .firstOrNull;

      final labelColor = styleElem
          .findAllElements('LabelStyle')
          .expand((e) => e.findElements('color'))
          .map((e) => _parseKmlColor(e.text))
          .firstOrNull;

      final labelScale = styleElem
          .findAllElements('LabelStyle')
          .expand((e) => e.findElements('scale'))
          .map((e) => double.tryParse(e.text))
          .firstOrNull;

      final lineColor = styleElem
          .findAllElements('LineStyle')
          .expand((e) => e.findElements('color'))
          .map((e) => _parseKmlColor(e.text))
          .firstOrNull;

      final lineWidth = styleElem
          .findAllElements('LineStyle')
          .expand((e) => e.findElements('width'))
          .map((e) => double.tryParse(e.text))
          .firstOrNull;

      final polyColor = styleElem
          .findAllElements('PolyStyle')
          .expand((e) => e.findElements('color'))
          .map((e) => _parseKmlColor(e.text))
          .firstOrNull;

      styles['#$id'] = KmlStyle(
        id: id,
        iconHref: iconHref,
        iconScale: iconScale,
        labelColor: labelColor,
        labelScale: labelScale,
        lineColor: lineColor,
        lineWidth: lineWidth,
        polyColor: polyColor,
      );
    }
  }

  List<Marker> parsePlacemarks() {
    final placemarks = <Marker>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final name = pm.getElement('name')?.text ?? '';
      final styleUrl = pm.getElement('styleUrl')?.text ?? '';
      final coordText =
          pm.findAllElements('coordinates').map((e) => e.text).firstOrNull;

      final pointElem = pm.findAllElements('Point').firstOrNull;
      if (coordText == null || pointElem == null) continue;

      final parts = coordText.trim().split(',');
      if (parts.length < 2) continue;

      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);

      if (lat == null || lon == null) continue;

      final style = styles[styleUrl];
      Widget iconWidget = const Icon(Icons.place, color: Colors.red);

      if (style?.iconHref != null) {
        final href = style!.iconHref!;
        if (href.startsWith('http')) {
          iconWidget = Image.network(
            href,
            width: 30 * (style.iconScale ?? 1.0),
            height: 30 * (style.iconScale ?? 1.0),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.warning, color: Colors.orange),
          );
        } else {
          iconWidget = Image.asset(
            'assets/icons/$href',
            width: 30 * (style.iconScale ?? 1.0),
            height: 30 * (style.iconScale ?? 1.0),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.warning, color: Colors.orange),
          );
        }
      }

      placemarks.add(
        Marker(
          point: LatLng(lat, lon),
          width: 40,
          height: 40,
          child: Column(
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 10 * (style?.labelScale ?? 1.0),
                  color: style?.labelColor ?? Colors.purple,
                ),
              ),
              iconWidget,
            ],
          ),
        ),
      );
    }

    return placemarks;
  }

  List<Polyline> parsePolylines() {
    final lines = <Polyline>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final lineString = pm.findAllElements('LineString').firstOrNull;
      final coords = lineString?.findElements('coordinates').firstOrNull?.text;
      final styleUrl = pm.getElement('styleUrl')?.text ?? '';
      if (coords == null) continue;

      final points = coords
          .trim()
          .split(RegExp(r'\s+'))
          .map((c) {
            final parts = c.split(',');
            if (parts.length < 2) return null;
            final lon = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat == null || lon == null) return null;
            return LatLng(lat, lon);
          })
          .whereType<LatLng>()
          .toList();

      final style = styles[styleUrl];

      lines.add(Polyline(
        points: points,
        strokeWidth: style?.lineWidth ?? 3.0,
        color: style?.lineColor ?? Colors.blue,
      ));
    }

    return lines;
  }

  List<Polygon> parsePolygons() {
    final polygons = <Polygon>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final polyElem = pm.findAllElements('Polygon').firstOrNull;
      final coords = polyElem
          ?.findAllElements('outerBoundaryIs')
          .expand((e) => e.findElements('LinearRing'))
          .expand((e) => e.findElements('coordinates'))
          .map((e) => e.text)
          .firstOrNull;

      final styleUrl = pm.getElement('styleUrl')?.text ?? '';
      if (coords == null) continue;

      final points = coords
          .trim()
          .split(RegExp(r'\s+'))
          .map((c) {
            final parts = c.split(',');
            if (parts.length < 2) return null;
            final lon = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat == null || lon == null) return null;
            return LatLng(lat, lon);
          })
          .whereType<LatLng>()
          .toList();

      final style = styles[styleUrl];

      polygons.add(Polygon(
        points: points,
        color: (style?.polyColor ?? Colors.green).withOpacity(0.4),
        borderColor: style?.lineColor ?? Colors.black,
        borderStrokeWidth: style?.lineWidth ?? 2.0,
      ));
    }

    return polygons;
  }

  Color _parseKmlColor(String kmlColor) {
    // KML usa AABBGGRR
    if (kmlColor.length != 8) return Colors.black;
    final a = int.parse(kmlColor.substring(0, 2), radix: 16);
    final b = int.parse(kmlColor.substring(2, 4), radix: 16);
    final g = int.parse(kmlColor.substring(4, 6), radix: 16);
    final r = int.parse(kmlColor.substring(6, 8), radix: 16);
    return Color.fromARGB(a, r, g, b);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
