import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
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

  String _cleanHtml(String html) {
    if (!html.contains('<')) return html;

    // Remove all tags
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    String result = html.replaceAll(exp, '');

    // Simple entity decoding
    result = result
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n\n', '\n');

    return result.trim();
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

  List<LabeledMarker> parsePlacemarks() {
    final labeledMarkers = <LabeledMarker>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final name = pm.getElement('name')?.text ?? '';
      final description = pm.getElement('description')?.text ?? '';
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

      // Extract metadata
      String locality = '';
      String manualCoordinates = '';
      String observation = _cleanHtml(description);
      final Map<String, String> attributes = {};

      final extendedData = pm.getElement('ExtendedData');
      if (extendedData != null) {
        for (final data in extendedData.findAllElements('Data')) {
          final key = data.getAttribute('name');
          final value = data.getElement('value')?.text;
          if (key != null && value != null) {
            attributes[key] = value;
            if (key.toLowerCase().contains('localidad') ||
                key.toLowerCase().contains('locality')) {
              locality = value;
            } else if (key.toLowerCase().contains('coord') ||
                key.toLowerCase().contains('manual')) {
              manualCoordinates = value;
            } else if (key.toLowerCase().contains('obs') ||
                key.toLowerCase().contains('note')) {
              observation = value;
            }
          }
        }
      }

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

      labeledMarkers.add(
        LabeledMarker(
          marker: Marker(
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
          label: name,
          locality: locality,
          manualCoordinates: manualCoordinates,
          observation: observation,
          geometry: GeometryData(
            name: name,
            type: 'point',
            coordinates: [LatLng(lat, lon)],
          ),
          attributes: attributes,
        ),
      );
    }

    return labeledMarkers;
  }

  List<LabeledPolyline> parsePolylines() {
    final lines = <LabeledPolyline>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final lineString = pm.findAllElements('LineString').firstOrNull;
      final coords = lineString?.findElements('coordinates').firstOrNull?.text;
      final name = pm.getElement('name')?.text ?? '';
      final description = pm.getElement('description')?.text ?? '';
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

      // Extract metadata
      String locality = '';
      String manualCoordinates = '';
      String observation = _cleanHtml(description);
      final Map<String, String> attributes = {};

      final extendedData = pm.getElement('ExtendedData');
      if (extendedData != null) {
        for (final data in extendedData.findAllElements('Data')) {
          final key = data.getAttribute('name');
          final value = data.getElement('value')?.text;
          if (key != null && value != null) {
            attributes[key] = value;
            if (key.toLowerCase().contains('localidad') ||
                key.toLowerCase().contains('locality')) {
              locality = value;
            } else if (key.toLowerCase().contains('coord') ||
                key.toLowerCase().contains('manual')) {
              manualCoordinates = value;
            } else if (key.toLowerCase().contains('obs') ||
                key.toLowerCase().contains('note')) {
              observation = value;
            }
          }
        }
      }

      lines.add(LabeledPolyline(
        polyline: Polyline(
          points: points,
          strokeWidth: style?.lineWidth ?? 3.0,
          color: style?.lineColor ?? Colors.blue,
        ),
        label: name,
        locality: locality,
        manualCoordinates: manualCoordinates,
        observation: observation,
        attributes: attributes,
      ));
    }

    return lines;
  }

  List<LabeledPolygon> parsePolygons() {
    final polygons = <LabeledPolygon>[];

    for (final pm in xml.findAllElements('Placemark')) {
      final poly = pm.findAllElements('Polygon').firstOrNull;
      if (poly == null) continue;

      final name = pm.getElement('name')?.text ?? '';
      final description = pm.getElement('description')?.text ?? '';
      final styleUrl = pm.getElement('styleUrl')?.text ?? '';

      final outerBoundary = poly.findAllElements('outerBoundaryIs').firstOrNull;
      if (outerBoundary == null) continue;

      final linearRing = outerBoundary.findAllElements('LinearRing').firstOrNull;
      if (linearRing == null) continue;

      final coordText =
          linearRing.findAllElements('coordinates').firstOrNull?.text;
      if (coordText == null) continue;

      final points = coordText
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

      if (points.isEmpty) continue;

      final style = styles[styleUrl];

      // Extract metadata
      String locality = '';
      String manualCoordinates = '';
      String observation = _cleanHtml(description);
      final Map<String, String> attributes = {};

      final extendedData = pm.getElement('ExtendedData');
      if (extendedData != null) {
        for (final data in extendedData.findAllElements('Data')) {
          final key = data.getAttribute('name');
          final value = data.getElement('value')?.text;
          if (key != null && value != null) {
            attributes[key] = value;
            if (key.toLowerCase().contains('localidad') ||
                key.toLowerCase().contains('locality')) {
              locality = value;
            } else if (key.toLowerCase().contains('coord') ||
                key.toLowerCase().contains('manual')) {
              manualCoordinates = value;
            } else if (key.toLowerCase().contains('obs') ||
                key.toLowerCase().contains('note')) {
              observation = value;
            }
          }
        }
      }

      polygons.add(LabeledPolygon(
        polygon: Polygon(
          points: points,
          color: style?.polyColor ?? Colors.blue.withOpacity(0.3),
          isFilled: true,
          borderStrokeWidth: style?.lineWidth ?? 2.0,
          borderColor: style?.lineColor ?? Colors.blue,
        ),
        label: name,
        locality: locality,
        manualCoordinates: manualCoordinates,
        observation: observation,
        attributes: attributes,
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
