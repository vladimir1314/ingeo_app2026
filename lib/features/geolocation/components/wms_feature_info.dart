import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class WmsFeatureInfo {
  static Future<void> getFeatureInfo({
    required BuildContext context,
    required MapController mapController,
    required Map<String, bool> layerStates,
    required Offset tapXY,
    required Size viewportSize,
    required LatLng point,
  }) async {
    final activeWmsLayers = layerStates.entries
        .where((entry) => entry.value && entry.key.startsWith('sp_'));

    if (activeWmsLayers.isEmpty) return;

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
      for (var layer in activeWmsLayers) {
        final url = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/wms')
            .replace(queryParameters: {
          'SERVICE': 'WMS',
          'VERSION': '1.1.1',
          'REQUEST': 'GetFeatureInfo',
          'LAYERS': 'ingeo:${layer.key}',
          'QUERY_LAYERS': 'ingeo:${layer.key}',
          'INFO_FORMAT': 'application/json',
          'X': x.toString(),
          'Y': y.toString(),
          'WIDTH': width.toString(),
          'HEIGHT': height.toString(),
          'SRS': 'EPSG:4326',
          'BBOX':
              '${bounds?.west},${bounds?.south},${bounds?.east},${bounds?.north}',
        }).toString();

        // Añadir autenticación básica
        final credentials =
            base64Encode(utf8.encode('geoserver_ingeo:IdeasG@ingeo'));
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Basic $credentials',
          },
        );
        final bodyPreview = response.body.length > 500
            ? '${response.body.substring(0, 500)}…'
            : response.body;
        debugPrint('GET $url');
        debugPrint('statusCode=${response.statusCode}');
        debugPrint('bodyPreview=$bodyPreview');

        if (response.statusCode == 200) {
          final features = json.decode(response.body);
          debugPrint('Features: $features');
          if (features['features']?.isNotEmpty == true) {
            Navigator.of(context).pop(); // cierra loader

            await showDialog(
              context: context,
              builder: (context) => _FeatureInfoDialog(
                layerName: layer.key,
                properties: features['features'][0]['properties'],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _FeatureInfoDialog extends StatelessWidget {
  final String layerName;
  final Map<String, dynamic> properties;

  const _FeatureInfoDialog({
    required this.layerName,
    required this.properties,
  });

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
                            horizontal: 8, vertical: 4),
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
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 14),
                      ),
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
