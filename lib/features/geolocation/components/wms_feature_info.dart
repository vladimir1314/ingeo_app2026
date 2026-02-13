import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/wms_layer.dart';
import 'package:xml/xml.dart';

class WmsFeatureInfo {
  static Future<void> getFeatureInfo({
    required BuildContext context,
    required MapController mapController,
    required Map<String, bool> layerStates,
    required Offset tapXY,
    required Size viewportSize,
    required LatLng point,
    List<WmsLayer> customWmsLayers = const [],
  }) async {
    final activeLayers = layerStates.entries.where((entry) {
      if (!entry.value) return false;
      if (entry.key.startsWith('sp_')) return true;
      if (customWmsLayers.any((l) => l.id == entry.key)) return true;
      return false;
    }).toList();

    if (activeLayers.isEmpty) return;

    final bounds = mapController.bounds;
    final width = viewportSize.width.round();
    final height = viewportSize.height.round();
    final x = tapXY.dx.round();
    final y = tapXY.dy.round();

    // Loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      for (var entry in activeLayers) {
        String baseUrl;
        String layerName;
        String displayName;
        bool useAuth = false;

        if (entry.key.startsWith('sp_')) {
          baseUrl = 'http://84.247.176.139:8080/geoserver/ingeo/wms';
          layerName = 'ingeo:${entry.key}';
          displayName = entry.key; // Fallback for internal layers
          useAuth = true;
        } else {
          final customLayer = customWmsLayers.firstWhere(
            (l) => l.id == entry.key,
          );
          baseUrl = customLayer.url;
          layerName = customLayer.layerName;
          displayName = customLayer.name; // Use friendly name
          // Check if it's the same internal server to use auth
          if (baseUrl.contains('84.247.176.139')) {
            useAuth = true;
          }
        }

        // Clean baseUrl if it has query parameters
        final uriObj = Uri.parse(baseUrl);
        final baseUri = uriObj.replace(queryParameters: {});

        final url = baseUri
            .replace(
              queryParameters: {
                ...uriObj.queryParameters,
                'SERVICE': 'WMS',
                'VERSION': '1.1.1',
                'REQUEST': 'GetFeatureInfo',
                'LAYERS': layerName,
                'QUERY_LAYERS': layerName,
                'INFO_FORMAT': 'application/json',
                'X': x.toString(),
                'Y': y.toString(),
                'WIDTH': width.toString(),
                'HEIGHT': height.toString(),
                'SRS': 'EPSG:4326',
                'BBOX':
                    '${bounds?.west},${bounds?.south},${bounds?.east},${bounds?.north}',
              },
            )
            .toString();

        Map<String, String> headers = {};
        if (useAuth) {
          final credentials = base64Encode(
            utf8.encode('geoserver_ingeo:IdeasG@ingeo'),
          );
          headers['Authorization'] = 'Basic $credentials';
        }

        final response = await http.get(Uri.parse(url), headers: headers);
        
        String body;
        try {
          body = utf8.decode(response.bodyBytes).trim();
        } catch (_) {
          body = response.body.trim();
        }

        final bodyPreview = body.length > 500
            ? '${body.substring(0, 500)}…'
            : body;
        debugPrint('GET $url');
        debugPrint('statusCode=${response.statusCode}');
        debugPrint('bodyPreview=$bodyPreview');

        if (response.statusCode == 200) {
          final contentType = response.headers['content-type'] ?? '';
          Map<String, dynamic> properties = {};

          if (body.startsWith('<')) {
            // Try parsing as XML (ESRI/ArcGIS often returns XML for GetFeatureInfo)
            try {
              final document = XmlDocument.parse(body);
              // Search for FIELDS element (common in ESRI responses)
              final fields = document.findAllElements('FIELDS');
              if (fields.isNotEmpty) {
                // Extract attributes from the first FIELDS element
                for (final attr in fields.first.attributes) {
                  properties[attr.name.local] = attr.value;
                }
              } else {
                // Fallback: Try to find any element with attributes in FeatureInfoResponse
                final root = document.rootElement;
                for (final child in root.descendantElements) {
                  if (child.attributes.isNotEmpty) {
                     for (final attr in child.attributes) {
                      properties[attr.name.local] = attr.value;
                    }
                    if (properties.isNotEmpty) break; 
                  }
                }
              }
            } catch (e) {
              debugPrint('Error parsing XML: $e');
              // Fallback: Regex extraction for malformed XML or strict parser issues
              _extractAttributesWithRegex(body, properties);
            }
          } else {
            // Try parsing as JSON
            try {
              final features = json.decode(body);
              debugPrint('Features: $features');
              if (features['features']?.isNotEmpty == true) {
                properties = features['features'][0]['properties'];
              }
            } catch (e) {
              debugPrint('Error parsing JSON: $e');
            }
          }

          if (properties.isNotEmpty) {
            Navigator.of(context).pop(); // cierra loader

            await showDialog(
              context: context,
              builder: (context) => _FeatureInfoDialog(
                layerName: displayName,
                properties: properties,
              ),
            );
            return;
          }
        }
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró información.')),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
  static void _extractAttributesWithRegex(
    String body,
    Map<String, dynamic> properties,
  ) {
    // Attempt to extract key="value" pairs using regex
    // This is a fallback for when XML parsing fails
    try {
      final regex = RegExp(r'([a-zA-Z0-9_\.]+)="([^"]*)"');
      final matches = regex.allMatches(body);
      for (final match in matches) {
        if (match.groupCount >= 2) {
          final key = match.group(1);
          final value = match.group(2);
          if (key != null &&
              value != null &&
              key != 'xmlns' &&
              !key.startsWith('xmlns:')) {
            properties[key] = value;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in regex fallback: $e');
    }
  }
}

class _FeatureInfoDialog extends StatelessWidget {
  final String layerName;
  final Map<String, dynamic> properties;

  const _FeatureInfoDialog({required this.layerName, required this.properties});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Información de la capa\n"$layerName"',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: IntrinsicWidth(
          stepWidth: 200, // ancho mínimo para alinear
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: properties.entries.map((entry) {
              final key = entry.key;
              final value = entry.value?.toString() ?? 'N/A';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(value, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
