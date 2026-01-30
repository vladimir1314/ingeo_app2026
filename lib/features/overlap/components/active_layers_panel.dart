import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:ingeo_app/models/wms_layer.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:utm/utm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:turf/turf.dart' as turf;

class ActiveLayersPanel extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onClose;
  final Map<String, bool> layerStates;
  final List<LayerGroup> layerGroups;
  final List<SavedDrawingLayer> savedLayers;
  final void Function(String, bool) onLayerToggle;
  final Function(WmsLayer)? onWmsLayerAdd;
  final Function(SavedDrawingLayer)? onSaveGeometry;
  final Function(SavedDrawingLayer)? onIntersectionResult;

  const ActiveLayersPanel({
    super.key,
    required this.isVisible,
    required this.onClose,
    required this.layerStates,
    required this.layerGroups,
    required this.savedLayers,
    required this.onLayerToggle,
    this.onWmsLayerAdd,
    this.onSaveGeometry,
    this.onIntersectionResult,
  });

  Future<List<File>?> _generateIntersection(
    BuildContext context,
    String fileName,
  ) async {
    try {
      // Obtener capas de dibujo activas
      final activeDrawingLayers = layerStates.entries
          .where(
            (entry) =>
                entry.value == true && entry.key.startsWith('saved_layer_'),
          )
          .map(
            (entry) => savedLayers.firstWhere((layer) => layer.id == entry.key),
          )
          .toList();

      // Obtener capas temáticas activas (externas, SP o WMS)
      final activeThematicLayers = layerStates.entries
          .where((entry) => entry.value == true && entry.key.startsWith('sp_'))
          .map((entry) => entry.key)
          .toList();

      print('Capas de dibujo activas: ${activeDrawingLayers.length}');
      for (var layer in activeDrawingLayers) {
        print('Capa: ${layer.name}, ID: ${layer.id}');
        print('  - Puntos: ${layer.points?.length ?? 0}');
        print('  - Líneas: ${layer.lines?.length ?? 0}');
        print('  - Polígonos: ${layer.polygons?.length ?? 0}');
        if (layer.polygons.isNotEmpty) {
          print('  - Detalles de polígonos:');
          for (int i = 0; i < layer.polygons.length; i++) {
            final polygon = layer.polygons[i];
            print('    * Polígono $i: ${polygon.polygon.points.length} puntos');
            if (polygon.polygon.points.isNotEmpty) {
              print(
                '      Primer punto: (${polygon.polygon.points.first.latitude}, ${polygon.polygon.points.first.longitude})',
              );
              print(
                '      Último punto: (${polygon.polygon.points.last.latitude}, ${polygon.polygon.points.last.longitude})',
              );
            }
          }
        }
      }

      print('Capas temáticas activas: ${activeThematicLayers.length}');
      for (var layerId in activeThematicLayers) {
        print('Capa temática: $layerId');
      }

      // Validar que haya al menos una capa de dibujo y una capa temática
      if (activeDrawingLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay capas de dibujo activas')),
        );
        return null;
      }
      if (activeThematicLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay capas temáticas activas')),
        );
        return null;
      }

      // Verificar que al menos una capa de dibujo tenga geometrías válidas
      bool hasValidDrawingLayer = false;
      for (var layer in activeDrawingLayers) {
        if ((layer.points != null && layer.points.isNotEmpty) ||
            (layer.polygons != null && layer.polygons.isNotEmpty) ||
            (layer.lines != null && layer.lines.isNotEmpty)) {
          hasValidDrawingLayer = true;
          break;
        }
      }
      if (!hasValidDrawingLayer) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Las capas de dibujo no contienen geometrías válidas. Dibuje un polígono primero.',
            ),
          ),
        );
        return null;
      }

      // Procesar cada capa de dibujo con todas las capas temáticas
      final queryCode = fileName;
      final Map<String, Map<String, dynamic>> allResults = {};
      for (var drawingLayer in activeDrawingLayers) {
        print('Procesando capa de dibujo: ${drawingLayer.name}');

        if (drawingLayer.polygons != null && drawingLayer.polygons.isNotEmpty) {
          print('La capa tiene ${drawingLayer.polygons.length} polígonos');
          for (
            int polyIndex = 0;
            polyIndex < drawingLayer.polygons.length;
            polyIndex++
          ) {
            final polygon = drawingLayer.polygons[polyIndex];
            final points = polygon.polygon.points;
            print('Procesando polígono $polyIndex con ${points.length} puntos');

            // Construir WKT
            final wktBuilder = StringBuffer('POLYGON((');
            for (int i = 0; i < points.length; i++) {
              wktBuilder.write('${points[i].longitude} ${points[i].latitude}');
              if (i < points.length - 1) {
                wktBuilder.write(',');
              }
            }
            if (points.first.latitude != points.last.latitude ||
                points.first.longitude != points.last.longitude) {
              wktBuilder.write(
                ',${points.first.longitude} ${points.first.latitude}',
              );
            }
            wktBuilder.write('))');
            final wktPolygon = wktBuilder.toString();
            print('WKT Polygon: $wktPolygon');

            // Consultar cada capa temática
            for (var thematicLayerId in activeThematicLayers) {
              print('Procesando capa temática: $thematicLayerId');
              try {
                final results = await _fetchIntersectionForLayer(
                  layerName: thematicLayerId,
                  wktPolygon: wktPolygon,
                  drawingName: drawingLayer.name,
                );
                final features = results['features'] as List<dynamic>? ?? [];
                if (features.isNotEmpty) {
                  print(
                    'Resultados encontrados para $thematicLayerId: ${features.length}',
                  );
                  if (!allResults.containsKey(thematicLayerId)) {
                    allResults[thematicLayerId] = {
                      'type': 'FeatureCollection',
                      'features': <dynamic>[],
                    };
                    print(
                      'Inicializando FeatureCollection para $thematicLayerId',
                    );
                  }
                  final polyLabelRaw = (polygon.label?.toString() ?? '').trim();
                  final input1 = polyLabelRaw.isNotEmpty
                      ? polyLabelRaw
                      : 'Pol_${polyIndex + 1}';

                  final feats = features.map((f) {
                    final m = Map<String, dynamic>.from(f as Map);
                    final props = Map<String, dynamic>.from(
                      (m['properties'] as Map?) ?? {},
                    );
                    props['__drawing_name'] = drawingLayer.name;
                    props['__input1'] = input1;
                    m['properties'] = props;
                    return m;
                  }).toList();
                  (allResults[thematicLayerId]!['features'] as List).addAll(
                    feats,
                  );
                  print(
                    'Acumulando features. Total ahora en $thematicLayerId: ${(allResults[thematicLayerId]!['features'] as List).length}',
                  );
                } else {
                  print('No se encontraron resultados para $thematicLayerId');
                }
              } catch (e) {
                print('Error al procesar capa $thematicLayerId: $e');
              }
            }
          }
        }
        if (drawingLayer.lines != null && drawingLayer.lines.isNotEmpty) {
          print('La capa tiene ${drawingLayer.lines.length} líneas');

          for (
            int lineIndex = 0;
            lineIndex < drawingLayer.lines.length;
            lineIndex++
          ) {
            final labeledLine = drawingLayer.lines[lineIndex];
            final pts = labeledLine.polyline.points;

            if (pts.length < 2) {
              print('Línea $lineIndex: insuficientes puntos (${pts.length})');
              continue;
            }

            print(
              'Procesando línea $lineIndex: ${labeledLine.label}, ${pts.length} puntos',
            );
            final wktLine = _lineToWkt(pts);
            print('WKT Line: $wktLine');

            // Consultar cada capa temática
            for (var thematicLayerId in activeThematicLayers) {
              print('Procesando línea contra capa temática: $thematicLayerId');
              try {
                final feature = await _clipLineWithinLayer(
                  layerName: thematicLayerId,
                  wktLine: wktLine,
                  pts: pts,
                  label: labeledLine.label,
                  drawingName: drawingLayer.name,
                );

                if (feature != null) {
                  print('✅ Feature de línea encontrado para $thematicLayerId');

                  // Inicializar la capa en allResults si no existe
                  if (!allResults.containsKey(thematicLayerId)) {
                    allResults[thematicLayerId] = {
                      'type': 'FeatureCollection',
                      'features': <dynamic>[],
                    };
                    print(
                      'Inicializando FeatureCollection para $thematicLayerId',
                    );
                  }

                  // Agregar el feature a la lista de features
                  final m = Map<String, dynamic>.from(feature);
                  final props = Map<String, dynamic>.from(
                    (m['properties'] as Map?) ?? {},
                  );
                  props['__drawing_name'] = drawingLayer.name;
                  m['properties'] = props;
                  (allResults[thematicLayerId]!['features'] as List).add(m);
                  print(
                    'Feature agregado. Total features en $thematicLayerId: ${(allResults[thematicLayerId]!['features'] as List).length}',
                  );
                } else {
                  print(
                    '⚠️ No se encontró intersección para línea en $thematicLayerId',
                  );
                }
              } catch (e) {
                print('❌ Error al recortar línea en $thematicLayerId: $e');
                print('Stack trace: ${StackTrace.current}');
              }
            }
          }
        }
        if (drawingLayer.points != null && drawingLayer.points.isNotEmpty) {
          print('La capa tiene ${drawingLayer.points.length} puntos');

          for (
            int pointIndex = 0;
            pointIndex < drawingLayer.points.length;
            pointIndex++
          ) {
            final labeledPoint = drawingLayer.points[pointIndex];
            final pt = labeledPoint.marker.point;

            print(
              'Procesando punto $pointIndex: ${labeledPoint.label}, (${pt.latitude}, ${pt.longitude})',
            );
            final wktPoint = 'POINT(${pt.longitude} ${pt.latitude})';
            print('WKT Point: $wktPoint');

            // Consultar cada capa temática
            for (var thematicLayerId in activeThematicLayers) {
              print('Procesando punto contra capa temática: $thematicLayerId');
              try {
                final feature = await _checkPointWithinLayer(
                  layerName: thematicLayerId,
                  wktPoint: wktPoint,
                  pt: pt,
                  label: labeledPoint.label,
                  drawingName: drawingLayer.name,
                );

                if (feature != null) {
                  print('✅ Feature de punto encontrado para $thematicLayerId');

                  // Inicializar la capa en allResults si no existe
                  if (!allResults.containsKey(thematicLayerId)) {
                    allResults[thematicLayerId] = {
                      'type': 'FeatureCollection',
                      'features': <dynamic>[],
                    };
                    print(
                      'Inicializando FeatureCollection para $thematicLayerId',
                    );
                  }

                  // Agregar el feature a la lista de features
                  final m = Map<String, dynamic>.from(feature);
                  final props = Map<String, dynamic>.from(
                    (m['properties'] as Map?) ?? {},
                  );
                  props['__drawing_name'] = drawingLayer.name;
                  m['properties'] = props;
                  (allResults[thematicLayerId]!['features'] as List).add(m);
                  print(
                    'Feature agregado. Total features en $thematicLayerId: ${(allResults[thematicLayerId]!['features'] as List).length}',
                  );
                } else {
                  print(
                    '⚠️ No se encontró intersección para punto en $thematicLayerId',
                  );
                }
              } catch (e) {
                print('❌ Error al verificar punto en $thematicLayerId: $e');
                print('Stack trace: ${StackTrace.current}');
              }
            }
          }
        }
        if ((drawingLayer.points == null || drawingLayer.points.isEmpty) &&
            (drawingLayer.lines == null || drawingLayer.lines.isEmpty) &&
            (drawingLayer.polygons == null || drawingLayer.polygons.isEmpty)) {
          print('La capa ${drawingLayer.name} no tiene geometrías válidas');
          continue;
        }
      }

      print('═══════════════════════════════════════');
      print('RESUMEN FINAL DE RESULTADOS:');
      print('Total de capas con resultados: ${allResults.length}');
      for (var entry in allResults.entries) {
        final features = entry.value['features'] as List<dynamic>;
        print('  • ${entry.key}: ${features.length} features');
      }
      print('═══════════════════════════════════════');

      if (allResults.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron intersecciones geométricas'),
          ),
        );
        return null;
      }

      final kmzFile = await exportMultipleGeoJsonToKmz(allResults, fileName);
      final pdfFile = await _generateIntersectionPdfReport(
        allResults,
        activeDrawingLayers,
        activeThematicLayers,
        queryCode: queryCode,
      );

      // Crear capa de resultados para mostrar en el mapa
      if (onIntersectionResult != null) {
        final resultLayer = _createLayerFromResults(allResults, fileName);
        onIntersectionResult!(resultLayer);
      }

      return [kmzFile, pdfFile];
    } catch (e) {
      print('Error en _generateIntersection: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      return null;
    }
  }

  SavedDrawingLayer _createLayerFromResults(
    Map<String, Map<String, dynamic>> allResults,
    String fileName,
  ) {
    final List<LabeledPolyline> lines = [];
    final List<Polygon> polygons = [];
    final List<LabeledMarker> points = [];

    allResults.forEach((layerName, geoJson) {
      final features = geoJson['features'] as List<dynamic>;
      // Color base para esta capa temática
      final hexColor = _getColorForLayer(layerName);
      // Convertir ffaabbcc -> Color(0xffaabbcc)
      final colorVal = int.parse('0x$hexColor');
      final baseColor = Color(colorVal);

      for (var feature in features) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] as Map<String, dynamic>? ?? {};
        final geomType = geometry['type'] as String;
        final coords = geometry['coordinates'];
        final name = properties['name']?.toString() ?? 'Intersección';

        if (geomType == 'Polygon') {
          final outerRing = (coords[0] as List<dynamic>).map((coord) {
            return LatLng(
              (coord[1] is int
                  ? (coord[1] as int).toDouble()
                  : coord[1] as double),
              (coord[0] is int
                  ? (coord[0] as int).toDouble()
                  : coord[0] as double),
            );
          }).toList();

          polygons.add(
            Polygon(
              points: outerRing,
              color: baseColor.withOpacity(0.4),
              borderColor: baseColor,
              borderStrokeWidth: 2.0,
              isFilled: true,
              label: name,
            ),
          );
        } else if (geomType == 'MultiPolygon') {
          for (var polygon in coords) {
            final outerRing = (polygon[0] as List<dynamic>).map((coord) {
              return LatLng(
                (coord[1] is int
                    ? (coord[1] as int).toDouble()
                    : coord[1] as double),
                (coord[0] is int
                    ? (coord[0] as int).toDouble()
                    : coord[0] as double),
              );
            }).toList();

            polygons.add(
              Polygon(
                points: outerRing,
                color: baseColor.withOpacity(0.4),
                borderColor: baseColor,
                borderStrokeWidth: 2.0,
                isFilled: true,
                label: name,
              ),
            );
          }
        } else if (geomType == 'LineString') {
          final line = (coords as List<dynamic>).map((c) {
            return LatLng(
              (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
              (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
            );
          }).toList();

          lines.add(
            LabeledPolyline(
              polyline: Polyline(
                points: line,
                color: baseColor,
                strokeWidth: 4.0,
              ),
              label: name,
            ),
          );
        } else if (geomType == 'MultiLineString') {
          for (var lineCoords in (coords as List<dynamic>)) {
            final line = (lineCoords as List<dynamic>).map((c) {
              return LatLng(
                (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
                (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
              );
            }).toList();
            lines.add(
              LabeledPolyline(
                polyline: Polyline(
                  points: line,
                  color: baseColor,
                  strokeWidth: 4.0,
                ),
                label: name,
              ),
            );
          }
        } else if (geomType == 'Point') {
          final lon = (coords as List<dynamic>)[0];
          final lat = (coords as List<dynamic>)[1];
          final pt = LatLng(
            (lat is int ? lat.toDouble() : lat as double),
            (lon is int ? lon.toDouble() : lon as double),
          );

          points.add(
            LabeledMarker(
              marker: Marker(
                point: pt,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ),
              label: name,
              geometry: GeometryData(
                type: 'Point',
                name: name,
                coordinates: [pt],
              ),
            ),
          );
        }
      }
    });

    return SavedDrawingLayer(
      id: 'intersection_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Intersección ${DateTime.now().toString().split('.')[0]}',
      points: points,
      lines: lines,
      polygons: polygons
          .map((p) => LabeledPolygon(polygon: p, label: p.label ?? ''))
          .toList(),
      rawGeometries: [], // No necesitamos rawGeometries por ahora
      timestamp: DateTime.now(),
      attributes: {'source': 'intersection', 'fileName': fileName},
    );
  }

  Future<Map<String, dynamic>> _fetchIntersectionForLayer({
    required String layerName,
    required String wktPolygon,
    required String drawingName,
  }) async {
    print('Consultando recorte (clip) vía WPS para capa: $layerName');

    // Intento 1: WPS gs:Clip (el más adecuado para recortar)
    final wpsClipUrl = Uri.parse('http://84.247.176.139:8080/geoserver/wps');

    final clipXml =
        '''<?xml version="1.0" encoding="UTF-8"?>
<wps:Execute version="1.0.0" service="WPS"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://www.opengis.net/wps/1.0.0"
  xmlns:wfs="http://www.opengis.net/wfs"
  xmlns:wps="http://www.opengis.net/wps/1.0.0"
  xmlns:ows="http://www.opengis.net/ows/1.1"
  xmlns:gml="http://www.opengis.net/gml"
  xmlns:ogc="http://www.opengis.net/ogc"
  xmlns:wcs="http://www.opengis.net/wcs/1.1.1"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xsi:schemaLocation="http://www.opengis.net/wps/1.0.0 http://schemas.opengis.net/wps/1.0.0/wpsAll.xsd">
  <ows:Identifier>gs:Clip</ows:Identifier>
  <wps:DataInputs>
    <wps:Input>
      <ows:Identifier>features</ows:Identifier>
      <wps:Reference mimeType="text/xml" xlink:href="http://geoserver/wfs" method="POST">
        <wps:Body>
          <wfs:GetFeature service="WFS" version="1.0.0" outputFormat="GML2">
            <wfs:Query typeName="ingeo:$layerName"/>
          </wfs:GetFeature>
        </wps:Body>
      </wps:Reference>
    </wps:Input>
    <wps:Input>
      <ows:Identifier>clip</ows:Identifier>
      <wps:Data>
        <wps:ComplexData mimeType="application/wkt"><![CDATA[$wktPolygon]]></wps:ComplexData>
      </wps:Data>
    </wps:Input>
  </wps:DataInputs>
  <wps:ResponseForm>
    <wps:RawDataOutput mimeType="application/json">
      <ows:Identifier>result</ows:Identifier>
    </wps:RawDataOutput>
  </wps:ResponseForm>
</wps:Execute>''';

    const credentials = 'geoserver_ingeo:IdeasG@ingeo';
    final encodedCredentials = base64Encode(utf8.encode(credentials));

    try {
      final clipResp = await http.post(
        wpsClipUrl,
        headers: {
          'Authorization': 'Basic $encodedCredentials',
          'Content-Type': 'application/xml',
        },
        body: clipXml,
      );

      print('WPS Clip Status: ${clipResp.statusCode}');
      print(
        'WPS Clip Response: ${clipResp.body.substring(0, math.min(500, clipResp.body.length))}',
      );

      if (clipResp.statusCode == 200) {
        // Verificar si la respuesta es JSON
        if (clipResp.headers['content-type']?.contains('json') == true ||
            clipResp.body.trim().startsWith('{')) {
          try {
            final data = json.decode(clipResp.body) as Map<String, dynamic>;
            final feats = data['features'] as List<dynamic>? ?? [];
            if (feats.isNotEmpty) {
              print('✅ Clip WPS retornó ${feats.length} features recortadas');
              return data;
            }
          } catch (e) {
            print('Error parseando JSON del Clip: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error WPS Clip: $e');
    }

    // Intento 2: Usar GEOS directamente con CQL_FILTER y geometría
    print('Intentando filtro espacial con geometría explícita');
    try {
      final geomAttr = await _getGeometryAttributeName(layerName) ?? 'geom';

      // Usar el filtro CQL con WITHIN para obtener solo las geometrías dentro
      final cqlFilter = 'WITHIN($geomAttr, $wktPolygon)';

      final wfsUrl = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/ows')
          .replace(
            queryParameters: {
              'service': 'WFS',
              'version': '2.0.0',
              'request': 'GetFeature',
              'typeName': 'ingeo:$layerName',
              'outputFormat': 'application/json',
              'srsName': 'EPSG:4326',
              'CQL_FILTER': cqlFilter,
            },
          );

      final response = await http.get(
        wfsUrl,
        headers: {'Authorization': 'Basic $encodedCredentials'},
      );

      if (response.statusCode == 200) {
        final geoJson = json.decode(response.body) as Map<String, dynamic>;
        final features = geoJson['features'] as List<dynamic>? ?? [];

        if (features.isNotEmpty) {
          print('✅ CQL WITHIN retornó ${features.length} features');
          return geoJson;
        }
      }
    } catch (e) {
      print('Error con CQL WITHIN: $e');
    }

    // Intento 3: Último recurso - usar INTERSECTS pero advertir
    print('⚠️ Usando fallback INTERSECTS (puede incluir geometrías parciales)');
    final result = await _fetchIntersectViaWfs(
      layerName: layerName,
      wktPolygon: wktPolygon,
    );

    // Agregar advertencia en los resultados
    if (result['features'] != null && (result['features'] as List).isNotEmpty) {
      print(
        '⚠️ ADVERTENCIA: Los resultados pueden incluir geometrías completas que solo tocan el polígono',
      );
    }

    return result;
  }

  // Fallback: WFS GetFeature con INTERSECTS, salida JSON
  Future<Map<String, dynamic>> _fetchIntersectViaWfs({
    required String layerName,
    required String wktPolygon,
  }) async {
    final geomAttr = await _getGeometryAttributeName(layerName) ?? 'geom';
    final cql = 'INTERSECTS($geomAttr,SRID=4326;$wktPolygon)';
    final wfsUrl = Uri.parse(
      'http://84.247.176.139:8080/geoserver/ingeo/ows'
      '?service=WFS'
      '&version=1.0.0'
      '&request=GetFeature'
      '&typeName=ingeo:$layerName'
      '&outputFormat=application/json'
      '&srsName=EPSG:4326'
      '&CQL_FILTER=${Uri.encodeComponent(cql)}',
    );

    const credentials = 'geoserver_ingeo:IdeasG@ingeo';
    final encodedCredentials = base64Encode(utf8.encode(credentials));

    final response = await http.get(
      wfsUrl,
      headers: {'Authorization': 'Basic $encodedCredentials'},
    );

    if (response.statusCode != 200) {
      print('Error WFS HTTP ${response.statusCode}');
      print('Cuerpo: ${response.body}');
      throw Exception('Error WFS fallback en capa $layerName');
    }

    final geoJson = json.decode(response.body) as Map<String, dynamic>;
    print(
      'Fallback WFS INTERSECTS exitoso. Features: ${geoJson['features']?.length ?? 0}',
    );
    return geoJson;
  }

  String _lineToWkt(List<LatLng> pts) {
    final sb = StringBuffer('LINESTRING(');
    for (var i = 0; i < pts.length; i++) {
      sb.write('${pts[i].longitude} ${pts[i].latitude}');
      if (i < pts.length - 1) sb.write(',');
    }
    sb.write(')');
    return sb.toString();
  }

  Future<Map<String, dynamic>?> _clipLineWithinLayer({
    required String layerName,
    required String wktLine,
    required List<LatLng> pts,
    required String label,
    required String drawingName,
  }) async {
    try {
      print('🔍 Iniciando _clipLineWithinLayer para $layerName');
      final geomAttr = await _getGeometryAttributeName(layerName) ?? 'geom';
      print('Atributo de geometría: $geomAttr');

      final cql = 'INTERSECTS($geomAttr,SRID=4326;$wktLine)';
      print('CQL Filter: $cql');

      final wfsUrl = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/ows')
          .replace(
            queryParameters: {
              'service': 'WFS',
              'version': '2.0.0',
              'request': 'GetFeature',
              'typeName': 'ingeo:$layerName',
              'outputFormat': 'application/json',
              'srsName': 'EPSG:4326',
              'CQL_FILTER': cql,
            },
          );

      print('URL WFS: $wfsUrl');

      const credentials = 'geoserver_ingeo:IdeasG@ingeo';
      final encodedCredentials = base64Encode(utf8.encode(credentials));
      final resp = await http.get(
        wfsUrl,
        headers: {'Authorization': 'Basic $encodedCredentials'},
      );

      print('Respuesta HTTP: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        print('❌ Error HTTP: ${resp.body}');
        return null;
      }

      final geo = json.decode(resp.body) as Map<String, dynamic>;
      final feats = (geo['features'] as List?) ?? [];
      print('Features encontrados en WFS: ${feats.length}');

      if (feats.isEmpty) {
        print('⚠️ No hay features que intersecten');
        return null;
      }

      print('✅ Construyendo MultiPolygon WKT...');
      String multipolygonWkt = _buildMultiPolygonWktFromGeoJson(feats);
      if (multipolygonWkt.isEmpty) {
        print('❌ MultiPolygon WKT vacío');
        return null;
      }
      print(
        'MultiPolygon WKT: ${multipolygonWkt.substring(0, math.min(200, multipolygonWkt.length))}...',
      );

      print('🔧 Llamando a WPS JTS:intersection...');
      final wpsUrl = Uri.parse('http://84.247.176.139:8080/geoserver/wps');
      final xml =
          '''<?xml version="1.0" encoding="UTF-8"?>
<wps:Execute version="1.0.0" service="WPS"
 xmlns:wps="http://www.opengis.net/wps/1.0.0" xmlns:ows="http://www.opengis.net/ows/1.1">
  <ows:Identifier>JTS:intersection</ows:Identifier>
  <wps:DataInputs>
    <wps:Input>
      <ows:Identifier>geom1</ows:Identifier>
      <wps:Data>
        <wps:ComplexData mimeType="application/wkt"><![CDATA[$wktLine]]></wps:ComplexData>
      </wps:Data>
    </wps:Input>
    <wps:Input>
      <ows:Identifier>geom2</ows:Identifier>
      <wps:Data>
        <wps:ComplexData mimeType="application/wkt"><![CDATA[$multipolygonWkt]]></wps:ComplexData>
      </wps:Data>
    </wps:Input>
  </wps:DataInputs>
  <wps:ResponseForm>
    <wps:RawDataOutput mimeType="application/wkt">
      <ows:Identifier>result</ows:Identifier>
    </wps:RawDataOutput>
  </wps:ResponseForm>
</wps:Execute>''';

      final wpsResp = await http.post(
        wpsUrl,
        headers: {
          'Content-Type': 'text/xml',
          'Authorization': 'Basic $encodedCredentials',
        },
        body: xml,
      );

      print('WPS Response Status: ${wpsResp.statusCode}');

      if (wpsResp.statusCode == 200) {
        final wkt = wpsResp.body.trim();
        print('WPS Result WKT: ${wkt.substring(0, math.min(200, wkt.length))}');

        final feature = _wktLineToGeoJsonFeature(wkt, label);
        if (feature != null) {
          print('✅ Feature creado exitosamente desde WPS');
          return feature;
        }
        print('⚠️ _wktLineToGeoJsonFeature retornó null');
      } else {
        print('❌ WPS Error: ${wpsResp.body}');
      }

      // Fallback: recorte en cliente
      print('🔄 Usando fallback: recorte en cliente');
      final rings = _ringsFromGeoJsonFeatures(feats);
      print('Rings extraídos: ${rings.length}');

      final segments = _clipLineByRings(pts, rings);
      print('Segmentos después de clip: ${segments.length}');

      if (segments.isEmpty) {
        print('⚠️ No se generaron segmentos en el clip local');
        return null;
      }

      final feature = {
        'type': 'Feature',
        'properties': {'name': label},
        'geometry': {
          'type': segments.length == 1 ? 'LineString' : 'MultiLineString',
          'coordinates': segments.length == 1 ? segments.first : segments,
        },
      };
      print('✅ Feature creado con clip local');
      return feature;
    } catch (e, stackTrace) {
      print('❌ Error en _clipLineWithinLayer: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _checkPointWithinLayer({
    required String layerName, // Nombre de la capa temática a consultar
    required String wktPoint, // Punto en formato WKT: "POINT(lon lat)"
    required LatLng pt, // Punto original en formato LatLng
    required String label, // Etiqueta del punto
    required String drawingName,
  }) async {
    try {
      // 1. OBTENER NOMBRE DEL ATRIBUTO DE GEOMETRÍA
      print('🔍 Iniciando _checkPointWithinLayer para $layerName');
      final geomAttr = await _getGeometryAttributeName(layerName) ?? 'geom';
      print('Atributo de geometría: $geomAttr');

      // 2. CONSTRUIR FILTRO CQL
      // INTERSECTS verifica si el punto está DENTRO de las geometrías de la capa
      final cql = 'INTERSECTS($geomAttr,SRID=4326;$wktPoint)';
      print('CQL Filter: $cql');

      // 3. CONSTRUIR URL DE CONSULTA WFS
      final wfsUrl = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/ows')
          .replace(
            queryParameters: {
              'service': 'WFS',
              'version': '2.0.0',
              'request': 'GetFeature',
              'typeName': 'ingeo:$layerName',
              'outputFormat': 'application/json',
              'srsName': 'EPSG:4326',
              'CQL_FILTER': cql,
            },
          );

      print('URL WFS: $wfsUrl');

      // 4. HACER PETICIÓN HTTP
      const credentials = 'geoserver_ingeo:IdeasG@ingeo';
      final encodedCredentials = base64Encode(utf8.encode(credentials));
      final resp = await http.get(
        wfsUrl,
        headers: {'Authorization': 'Basic $encodedCredentials'},
      );

      print('Respuesta HTTP: ${resp.statusCode}');

      // 5. VALIDAR RESPUESTA
      if (resp.statusCode != 200) {
        print('❌ Error HTTP: ${resp.body}');
        return null;
      }

      // 6. PARSEAR GEOJSON
      final geo = json.decode(resp.body) as Map<String, dynamic>;
      final feats = (geo['features'] as List?) ?? [];
      print('Features encontrados en WFS: ${feats.length}');

      // 7. VERIFICAR SI HAY INTERSECCIONES
      if (feats.isEmpty) {
        print('⚠️ No hay features que contengan el punto');
        return null;
      }

      // 8. CONSTRUIR FEATURE DE RESPUESTA
      print('✅ Punto dentro de ${feats.length} geometría(s)');

      // Inicializar propiedades con el label del punto
      final properties = <String, dynamic>{
        '__input1': label,
        '__drawing_name': drawingName,
      };

      // 9. AGREGAR PROPIEDADES DE TODAS LAS GEOMETRÍAS QUE CONTIENEN EL PUNTO
      for (int i = 0; i < feats.length; i++) {
        final feat = feats[i];
        final featProps = feat['properties'] as Map<String, dynamic>? ?? {};

        // Si hay múltiples geometrías, prefijar propiedades con feature_N_
        featProps.forEach((key, value) {
          if (feats.length > 1) {
            properties['feature_${i + 1}_$key'] = value;
          } else {
            properties[key] = value;
          }
        });
      }

      // 10. CREAR FEATURE GEOJSON CON EL PUNTO
      final feature = {
        'type': 'Feature',
        'properties': properties,
        'geometry': {
          'type': 'Point',
          'coordinates': [pt.longitude, pt.latitude],
        },
      };

      print('✅ Feature de punto creado exitosamente');
      return feature;
    } catch (e, stackTrace) {
      print('❌ Error en _checkPointWithinLayer: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  String _buildMultiPolygonWktFromGeoJson(List<dynamic> features) {
    final polys = <String>[];
    for (var f in features) {
      final geom = f['geometry'];
      final type = geom['type'];
      final coords = geom['coordinates'];
      if (type == 'Polygon') {
        final ring = (coords[0] as List).map((c) => '${c[0]} ${c[1]}').toList();
        if (ring.isEmpty) continue;
        if (ring.first != ring.last) ring.add(ring.first);
        polys.add('((${ring.join(',')}))');
      } else if (type == 'MultiPolygon') {
        for (var poly in (coords as List)) {
          final ring = (poly[0] as List).map((c) => '${c[0]} ${c[1]}').toList();
          if (ring.isEmpty) continue;
          if (ring.first != ring.last) ring.add(ring.first);
          polys.add('((${ring.join(',')}))');
        }
      }
    }
    if (polys.isEmpty) return '';
    return 'MULTIPOLYGON(${polys.join(',')})';
  }

  Map<String, dynamic>? _wktLineToGeoJsonFeature(String wkt, String label) {
    if (wkt.isEmpty || wkt.contains('GEOMETRYCOLLECTION EMPTY')) return null;
    if (wkt.startsWith('MULTILINESTRING')) {
      final inner = wkt.substring('MULTILINESTRING'.length).trim();
      final content = inner.substring(1, inner.length - 1);
      final parts = content.split('),(');
      final lines = parts.map((p) {
        final s = p.replaceAll('(', '').replaceAll(')', '');
        final coords = s.split(',').map((pt) {
          final xy = pt.trim().split(' ');
          return [double.parse(xy[0]), double.parse(xy[1])];
        }).toList();
        return coords;
      }).toList();
      return {
        'type': 'Feature',
        'properties': {'name': label},
        'geometry': {'type': 'MultiLineString', 'coordinates': lines},
      };
    } else if (wkt.startsWith('LINESTRING')) {
      final inner = wkt.substring('LINESTRING'.length).trim();
      final content = inner.substring(1, inner.length - 1);
      final coords = content.split(',').map((pt) {
        final xy = pt.trim().split(' ');
        return [double.parse(xy[0]), double.parse(xy[1])];
      }).toList();
      return {
        'type': 'Feature',
        'properties': {'name': label},
        'geometry': {'type': 'LineString', 'coordinates': coords},
      };
    }
    return null;
  }

  List<List<List<double>>> _ringsFromGeoJsonFeatures(List<dynamic> feats) {
    final rings = <List<List<double>>>[];
    for (var f in feats) {
      final geom = f['geometry'];
      final type = geom['type'];
      final coords = geom['coordinates'];
      if (type == 'Polygon') {
        final ring = (coords[0] as List)
            .map(
              (c) => [
                (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
                (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
              ],
            )
            .toList();
        rings.add(ring);
      } else if (type == 'MultiPolygon') {
        for (var poly in coords as List) {
          final ring = (poly[0] as List)
              .map(
                (c) => [
                  (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
                  (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
                ],
              )
              .toList();
          rings.add(ring);
        }
      }
    }
    return rings;
  }

  List<List<List<double>>> _clipLineByRings(
    List<LatLng> pts,
    List<List<List<double>>> rings,
  ) {
    final segments = <List<List<double>>>[];
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      // Chequear por cada polígono
      for (final ring in rings) {
        final segs = _clipSegmentByRing(a, b, ring);
        segments.addAll(segs);
      }
    }
    return segments;
  }

  List<List<List<double>>> _clipSegmentByRing(
    LatLng a,
    LatLng b,
    List<List<double>> ring,
  ) {
    final inters = <Map<String, dynamic>>[];
    for (int i = 0; i < ring.length - 1; i++) {
      final p = LatLng(ring[i][1], ring[i][0]);
      final q = LatLng(ring[i + 1][1], ring[i + 1][0]);
      final ip = _segmentIntersection(a, b, p, q);
      if (ip != null) {
        inters.add({'t': ip['t'], 'pt': ip['pt']});
      }
    }
    inters.sort((x, y) => (x['t'] as double).compareTo(y['t'] as double));
    final res = <List<List<double>>>[];
    bool inside = _pointInPolygon(a, ring);
    LatLng last = a;
    for (final it in inters) {
      final LatLng p = it['pt'] as LatLng;
      if (inside) {
        res.add([
          [last.longitude, last.latitude],
          [p.longitude, p.latitude],
        ]);
      }
      inside = !inside;
      last = p;
    }
    if (inside) {
      res.add([
        [last.longitude, last.latitude],
        [b.longitude, b.latitude],
      ]);
    }
    return res;
  }

  Map<String, dynamic>? _segmentIntersection(
    LatLng a,
    LatLng b,
    LatLng c,
    LatLng d,
  ) {
    final x1 = a.longitude, y1 = a.latitude;
    final x2 = b.longitude, y2 = b.latitude;
    final x3 = c.longitude, y3 = c.latitude;
    final x4 = d.longitude, y4 = d.latitude;
    final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (den == 0) return null;
    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
    final u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / den;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    final px = x1 + t * (x2 - x1);
    final py = y1 + t * (y2 - y1);
    return {'t': t, 'pt': LatLng(py, px)};
  }

  bool _pointInPolygon(LatLng p, List<List<double>> ring) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i][0], yi = ring[i][1];
      final xj = ring[j][0], yj = ring[j][1];
      final intersect =
          ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude <
              (xj - xi) * (p.latitude - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  Future<String?> _getGeometryAttributeName(String layerName) async {
    try {
      final url = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/ows')
          .replace(
            queryParameters: {
              'service': 'WFS',
              'version': '1.0.0',
              'request': 'DescribeFeatureType',
              'typeName': 'ingeo:$layerName',
            },
          );
      const credentials = 'geoserver_ingeo:IdeasG@ingeo';
      final encodedCredentials = base64Encode(utf8.encode(credentials));
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Basic $encodedCredentials'},
      );
      if (resp.statusCode != 200) return null;
      final body = resp.body;
      final match = RegExp('name="(\\w+)"\\s+type="gml:').firstMatch(body);
      if (match != null) return match.group(1);
      return null;
    } catch (_) {
      return null;
    }
  }

  // Detecta el tipo de geometría de una capa vía DescribeFeatureType (WFS)
  Future<String?> _getLayerGeometryType(String layerName) async {
    try {
      final url = Uri.parse('http://84.247.176.139:8080/geoserver/ingeo/ows')
          .replace(
            queryParameters: {
              'service': 'WFS',
              'version': '1.0.0',
              'request': 'DescribeFeatureType',
              'typeName': 'ingeo:$layerName',
            },
          );

      const credentials = 'geoserver_ingeo:IdeasG@ingeo';
      final encodedCredentials = base64Encode(utf8.encode(credentials));
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Basic $encodedCredentials'},
      );

      if (resp.statusCode != 200) {
        print('DescribeFeatureType fallo: HTTP ${resp.statusCode}');
        return null;
      }
      final body = resp.body;
      if (body.contains('gml:PointPropertyType')) return 'Point';
      if (body.contains('gml:PolygonPropertyType') ||
          body.contains('gml:MultiPolygonPropertyType'))
        return 'Polygon';
      if (body.contains('gml:LineStringPropertyType') ||
          body.contains('gml:MultiLineStringPropertyType'))
        return 'LineString';
      return null;
    } catch (e) {
      print('Error detectando geometría de $layerName: $e');
      return null;
    }
  }

  Future<File> exportMultipleGeoJsonToKmz(
    Map<String, Map<String, dynamic>> geoJsonResults,
    String fileName,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final archive = Archive();

    final filtered = <String, Map<String, dynamic>>{};
    for (final entry in geoJsonResults.entries) {
      final feats = entry.value['features'];
      if (feats is! List || feats.isEmpty) continue;

      final layerKey = entry.key.trim();
      if (filtered.containsKey(layerKey)) {
        final existing =
            (filtered[layerKey]!['features'] as List?) ?? <dynamic>[];
        existing.addAll(feats);
        filtered[layerKey]!['features'] = existing;
      } else {
        filtered[layerKey] = entry.value;
      }
    }

    if (filtered.isEmpty) {
      throw Exception('No hay intersecciones para exportar');
    }

    // doc.kml debe existir como KML raíz para que los visores carguen el consolidado
    final consolidatedKml = _createConsolidatedKml(filtered, fileName);
    final consolidatedKmlData = utf8.encode(consolidatedKml);
    archive.addFile(
      ArchiveFile('doc.kml', consolidatedKmlData.length, consolidatedKmlData),
    );
    archive.addFile(
      ArchiveFile(
        'CONSOLIDADO_$fileName.kml',
        consolidatedKmlData.length,
        consolidatedKmlData,
      ),
    );

    // KMLs individuales por capa
    for (final entry in filtered.entries) {
      final layerName = entry.key;
      final geoJson = entry.value;
      final kmlContent = _geoJsonToKml(geoJson, layerName);
      if (kmlContent.isNotEmpty) {
        final kmlData = utf8.encode(kmlContent);
        archive.addFile(
          ArchiveFile(
            '${_sanitizeFileName(layerName)}.kml',
            kmlData.length,
            kmlData,
          ),
        );
      }
    }

    final readmeContent = _createReadmeContent(filtered);
    final readmeData = utf8.encode(readmeContent);
    archive.addFile(ArchiveFile('README.txt', readmeData.length, readmeData));

    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);
    if (zipData == null) throw Exception('Failed to encode ZIP data');

    final kmzFile = File('${tempDir.path}/$fileName.kmz');
    await kmzFile.writeAsBytes(zipData, flush: true);
    return kmzFile;
  }

  String _createConsolidatedKml(
    Map<String, Map<String, dynamic>> geoJsonResults,
    String fileName,
  ) {
    final allPlacemarks = geoJsonResults.entries
        .map((entry) {
          final layerName = entry.key;
          final geoJson = entry.value;
          final features = geoJson['features'] as List<dynamic>;
          final displayName = layerName
              .replaceAll('sp_anp_nacionales_definidas', 'ANP Nacionales')
              .replaceAll(
                'sp_zonas_amortiguamiento',
                'Zonas de Amortiguamiento',
              )
              .replaceAll('sp_', '')
              .replaceAll('_', ' ');

          final placemarks = features
              .map((f) {
                final geometry = f['geometry'];
                final properties = f['properties'] ?? {};
                final geomType = geometry['type'] as String;
                final coords = geometry['coordinates'];

                String generateCoordinates(List<dynamic> ring) {
                  return ring
                      .map((c) {
                        final lon = (c as List<dynamic>)[0];
                        final lat = c[1];
                        return '$lon,$lat,0';
                      })
                      .join(' ');
                }

                if (geomType == 'MultiPolygon') {
                  final polygons = coords as List<dynamic>;
                  final polygonKml = polygons
                      .map((poly) {
                        if (poly is List<dynamic> && poly.isNotEmpty) {
                          final outerRing = poly[0] as List<dynamic>;
                          if (outerRing.isEmpty) return '';
                          final closedRing = List<dynamic>.from(outerRing);
                          if (closedRing.first != closedRing.last) {
                            closedRing.add(closedRing.first);
                          }
                          final coordinatesStr = generateCoordinates(
                            closedRing,
                          );
                          return '''
              <Polygon>
                <outerBoundaryIs>
                  <LinearRing>
                    <coordinates>$coordinatesStr</coordinates>
                  </LinearRing>
                </outerBoundaryIs>
              </Polygon>
            ''';
                        }
                        return '';
                      })
                      .where((kml) => kml.isNotEmpty)
                      .join('\n');
                  if (polygonKml.isEmpty) return '';

                  return '''
              <Placemark>
                <name>🔹 ${_escapeXml(properties['name']?.toString() ?? 'Intersección')} - $displayName</name>
                <description>📍 Capa: $displayName
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(layerName)}</color>
                    <width>2</width>
                  </LineStyle>
                  <PolyStyle>
                    <color>7d${_getColorForLayer(layerName).substring(2)}</color>
                    <fill>1</fill>
                    <outline>1</outline>
                  </PolyStyle>
                </Style>
                <MultiGeometry>
                  $polygonKml
                </MultiGeometry>
              </Placemark>
            ''';
                } else if (geomType == 'Polygon') {
                  final outerRing = coords[0] as List<dynamic>;
                  if (outerRing.isEmpty) return '';
                  final closedRing = List<dynamic>.from(outerRing);
                  if (closedRing.first != closedRing.last) {
                    closedRing.add(closedRing.first);
                  }
                  final coordinatesStr = generateCoordinates(closedRing);
                  return '''
              <Placemark>
                <name>🔹 ${_escapeXml(properties['name']?.toString() ?? 'Intersección')} - $displayName</name>
                <description>📍 Capa: $displayName
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(layerName)}</color>
                    <width>2</width>
                  </LineStyle>
                  <PolyStyle>
                    <color>7d${_getColorForLayer(layerName).substring(2)}</color>
                    <fill>1</fill>
                    <outline>1</outline>
                  </PolyStyle>
                </Style>
                <Polygon>
                  <outerBoundaryIs>
                    <LinearRing>
                      <coordinates>$coordinatesStr</coordinates>
                    </LinearRing>
                  </outerBoundaryIs>
                </Polygon>
              </Placemark>
              ''';
                } else if (geomType == 'LineString') {
                  final lineCoords = (coords as List<dynamic>)
                      .map((c) => '${(c[0])},${(c[1])},0')
                      .join(' ');
                  return '''
              <Placemark>
                <name>🔹 ${_escapeXml(properties['name']?.toString() ?? 'Segmento')} - $displayName</name>
                <description>📍 Capa: $displayName
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(layerName)}</color>
                    <width>3</width>
                  </LineStyle>
                </Style>
                <LineString>
                  <coordinates>$lineCoords</coordinates>
                </LineString>
              </Placemark>
            ''';
                } else if (geomType == 'MultiLineString') {
                  final lines = (coords as List<dynamic>)
                      .map((line) {
                        final lc = (line as List<dynamic>)
                            .map((c) => '${(c[0])},${(c[1])},0')
                            .join(' ');
                        return '<LineString><coordinates>$lc</coordinates></LineString>';
                      })
                      .join('\n');
                  return '''
              <Placemark>
                <name>🔹 ${_escapeXml(properties['name']?.toString() ?? 'Segmentos')} - $displayName</name>
                <description>📍 Capa: $displayName
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(layerName)}</color>
                    <width>3</width>
                  </LineStyle>
                </Style>
                <MultiGeometry>
                  $lines
                </MultiGeometry>
              </Placemark>
              ''';
                } else if (geomType == 'Point') {
                  final lon = (coords as List<dynamic>)[0];
                  final lat = (coords as List<dynamic>)[1];
                  return '''
              <Placemark>
                <name>🔹 ${_escapeXml(properties['name']?.toString() ?? 'Punto')} - $displayName</name>
                <description>📍 Capa: $displayName
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <IconStyle>
                    <color>${_getColorForLayer(layerName)}</color>
                  </IconStyle>
                </Style>
                <Point>
                  <coordinates>${lon},${lat},0</coordinates>
                </Point>
              </Placemark>
              ''';
                }
                return '';
              })
              .where((kml) => kml.isNotEmpty)
              .join('\n');

          if (placemarks.trim().isEmpty) return '';

          return '''
    <Folder>
      <name>${_escapeXml(displayName)}</name>
      $placemarks
    </Folder>
          ''';
        })
        .where((kml) => kml.isNotEmpty)
        .join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>🗺️ ${_escapeXml(fileName)}</name>
    <description>📊 Intersecciones consolidadas para ${geoJsonResults.length} capas:
${geoJsonResults.keys.map((k) => '• $k').join('\n')}</description>
    $allPlacemarks
  </Document>
</kml>''';
  }

  String _createReadmeContent(
    Map<String, Map<String, dynamic>> geoJsonResults,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('INTERSECCIONES GEOMÉTRICAS - INFORMACIÓN DEL ARCHIVO');
    buffer.writeln('====================================================');
    buffer.writeln('Generado: ${DateTime.now()}');
    buffer.writeln('Total de capas procesadas: ${geoJsonResults.length}');
    buffer.writeln('');
    buffer.writeln('DETALLE POR CAPA:');
    buffer.writeln('-----------------');
    geoJsonResults.forEach((layerName, geoJson) {
      final features = geoJson['features'] as List<dynamic>;
      buffer.writeln(
        '• $layerName: ${features.length} características encontradas',
      );
    });
    buffer.writeln('');
    buffer.writeln('CONTENIDO DEL KMZ:');
    buffer.writeln('------------------');
    buffer.writeln(
      '- CONSOLIDADO_[nombre].kml: Todas las intersecciones en un archivo',
    );
    geoJsonResults.forEach((layerName, _) {
      buffer.writeln(
        '- ${_sanitizeFileName(layerName)}.kml: Intersecciones individuales por capa',
      );
    });
    buffer.writeln('- README.txt: Este archivo de información');
    return buffer.toString();
  }

  String _getColorForLayer(String layerName) {
    final colors = {
      'sp_anp_nacionales_definidas': 'ff0000ff',
      'sp_zonas_amortiguamiento': 'ff00ff00',
      'wms_layer_': 'ffffff00',
      'external_layer_': 'ffff00ff',
    };
    for (final key in colors.keys) {
      if (layerName.contains(key)) {
        return colors[key]!;
      }
    }
    return 'ffff8000'; // Naranja
  }

  String _propertiesToDescription(Map<String, dynamic> properties) {
    return properties.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  String _geoJsonToKml(Map<String, dynamic> geoJson, String name) {
    try {
      final features = geoJson['features'] as List<dynamic>;
      final kmlFeatures = features
          .map((f) {
            final geometry = f['geometry'];
            final properties = f['properties'] ?? {};
            final geomType = geometry['type'] as String;
            final coords = geometry['coordinates'];

            String generateCoordinates(List<dynamic> ring) {
              return ring
                  .map((c) {
                    final lon = (c as List<dynamic>)[0];
                    final lat = c[1];
                    return '$lon,$lat,0';
                  })
                  .join(' ');
            }

            if (geomType == 'MultiPolygon') {
              final polygons = coords as List<dynamic>;
              final polygonKml = polygons
                  .map((poly) {
                    if (poly is List<dynamic> && poly.isNotEmpty) {
                      final outerRing = poly[0] as List<dynamic>;
                      if (outerRing.isEmpty) return '';
                      final closedRing = List<dynamic>.from(outerRing);
                      if (closedRing.first != closedRing.last) {
                        closedRing.add(closedRing.first);
                      }
                      final coordinatesStr = generateCoordinates(closedRing);
                      return '''
                      <Polygon>
                        <outerBoundaryIs>
                          <LinearRing>
                            <coordinates>$coordinatesStr</coordinates>
                          </LinearRing>
                        </outerBoundaryIs>
                      </Polygon>
                    ''';
                    }
                    return '';
                  })
                  .where((kml) => kml.isNotEmpty)
                  .join('\n');
              if (polygonKml.isEmpty) return '';

              return '''
              <Placemark>
                <name>${_escapeXml(properties['name']?.toString() ?? 'Intersección')}</name>
                <description>Capa: $name
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(name)}</color>
                    <width>2</width>
                  </LineStyle>
                  <PolyStyle>
                    <color>7d${_getColorForLayer(name).substring(2)}</color>
                    <fill>1</fill>
                    <outline>1</outline>
                  </PolyStyle>
                </Style>
                <MultiGeometry>
                  $polygonKml
                </MultiGeometry>
              </Placemark>
            ''';
            } else if (geomType == 'Polygon') {
              final outerRing = coords[0] as List<dynamic>;
              if (outerRing.isEmpty) return '';
              final closedRing = List<dynamic>.from(outerRing);
              if (closedRing.first != closedRing.last) {
                closedRing.add(closedRing.first);
              }
              final coordinatesStr = generateCoordinates(closedRing);
              return '''
              <Placemark>
                <name>${_escapeXml(properties['name']?.toString() ?? 'Intersección')}</name>
                <description>Capa: $name
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(name)}</color>
                    <width>2</width>
                  </LineStyle>
                  <PolyStyle>
                    <color>7d${_getColorForLayer(name).substring(2)}</color>
                    <fill>1</fill>
                    <outline>1</outline>
                  </PolyStyle>
                </Style>
                <Polygon>
                  <outerBoundaryIs>
                    <LinearRing>
                      <coordinates>$coordinatesStr</coordinates>
                    </LinearRing>
                  </outerBoundaryIs>
                </Polygon>
              </Placemark>
            ''';
            } else if (geomType == 'LineString') {
              final lineCoords = (coords as List<dynamic>)
                  .map((c) => '${(c[0])},${(c[1])},0')
                  .join(' ');
              return '''
              <Placemark>
                <name>${_escapeXml(properties['name']?.toString() ?? 'Segmento')}</name>
                <description>Capa: $name
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(name)}</color>
                    <width>3</width>
                  </LineStyle>
                </Style>
                <LineString>
                  <coordinates>$lineCoords</coordinates>
                </LineString>
              </Placemark>
            ''';
            } else if (geomType == 'MultiLineString') {
              final lines = (coords as List<dynamic>)
                  .map((line) {
                    final lc = (line as List<dynamic>)
                        .map((c) => '${(c[0])},${(c[1])},0')
                        .join(' ');
                    return '<LineString><coordinates>$lc</coordinates></LineString>';
                  })
                  .join('\n');
              return '''
              <Placemark>
                <name>${_escapeXml(properties['name']?.toString() ?? 'Segmentos')}</name>
                <description>Capa: $name
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <LineStyle>
                    <color>${_getColorForLayer(name)}</color>
                    <width>3</width>
                  </LineStyle>
                </Style>
                <MultiGeometry>
                  $lines
                </MultiGeometry>
              </Placemark>
            ''';
            } else if (geomType == 'Point') {
              final lon = (coords as List<dynamic>)[0];
              final lat = (coords as List<dynamic>)[1];
              return '''
              <Placemark>
                <name>${_escapeXml(properties['name']?.toString() ?? 'Punto')}</name>
                <description>Capa: $name
${_escapeXml(_propertiesToDescription(properties))}</description>
                <Style>
                  <IconStyle>
                    <color>${_getColorForLayer(name)}</color>
                  </IconStyle>
                </Style>
                <Point>
                  <coordinates>${lon},${lat},0</coordinates>
                </Point>
              </Placemark>
            ''';
            }
            return '';
          })
          .where((kml) => kml.isNotEmpty)
          .join('\n');

      return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${_escapeXml(name)}</name>
    <description>Intersecciones geométricas para capa: $name</description>
    $kmlFeatures
  </Document>
</kml>''';
    } catch (e) {
      print('Error generating KML: $e');
      return '';
    }
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '<')
        .replaceAll('>', '>')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _getLayerInfo(SavedDrawingLayer layer) {
    final List<String> info = [];
    if (layer.points.isNotEmpty) {
      info.add(
        '${layer.points.length} punto${layer.points.length != 1 ? 's' : ''}',
      );
    }
    if (layer.lines.isNotEmpty) {
      info.add(
        '${layer.lines.length} línea${layer.lines.length != 1 ? 's' : ''}',
      );
    }
    if (layer.polygons.isNotEmpty) {
      info.add(
        '${layer.polygons.length} polígono${layer.polygons.length != 1 ? 's' : ''}',
      );
    }
    return info.isEmpty ? 'Sin elementos' : info.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: isVisible ? 0 : -MediaQuery.of(context).size.width * 0.8,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.8,
      child: Material(
        elevation: 8,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Capas Activas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.layers,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Capas Activas',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${layerStates.values.where((v) => v == true).length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...layerGroups.map((group) {
                        final activeItems = group.items
                            .where((item) => layerStates[item.layerId] == true)
                            .toList();
                        if (activeItems.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      color: Colors.grey.shade600,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      group.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${activeItems.length}',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...activeItems.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                final isLast = index == activeItems.length - 1;
                                return Container(
                                  decoration: BoxDecoration(
                                    border: !isLast
                                        ? Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade200,
                                              width: 0.5,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Icon(
                                      Icons.visibility,
                                      color: Colors.green.shade600,
                                      size: 18,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }).toList(),
                      if (layerGroups.any(
                            (g) => g.items.any(
                              (i) => layerStates[i.layerId] == true,
                            ),
                          ) &&
                          savedLayers.any((l) => layerStates[l.id] == true))
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'DIBUJOS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (savedLayers.any((l) => layerStates[l.id] == true))
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: savedLayers
                                .where((layer) => layerStates[layer.id] == true)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                                  final index = entry.key;
                                  final layer = entry.value;
                                  final activeLayers = savedLayers
                                      .where((l) => layerStates[l.id] == true)
                                      .toList();
                                  final isLast =
                                      index == activeLayers.length - 1;
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: !isLast
                                          ? Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                                width: 0.5,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.draw,
                                          color: Colors.orange.shade600,
                                          size: 16,
                                        ),
                                      ),
                                      title: Text(
                                        layer.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        _getLayerInfo(layer),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.visibility,
                                        color: Colors.orange.shade600,
                                        size: 18,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.95),
                      Colors.grey.shade50,
                    ],
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.analytics_outlined,
                              color: Colors.teal.shade600,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Análisis de Superposición',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              Text(
                                'Genera intersecciones entre capas activas',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'Nombre de la superposición',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.edit_outlined,
                              color: Colors.grey.shade500,
                              size: 20,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              Colors.teal.shade600,
                              Colors.teal.shade700,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.teal.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Por favor, ingresa un nombre'),
                                    ],
                                  ),
                                  backgroundColor: Colors.orange.shade600,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                              return;
                            }

                            final nav = Navigator.of(
                              context,
                              rootNavigator: true,
                            );
                            bool dialogShown = false;
                            try {
                              showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                useRootNavigator: true,
                                builder: (_) => WillPopScope(
                                  onWillPop: () async => false,
                                  child: const AlertDialog(
                                    content: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            'Generando superposición...',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                              dialogShown = true;

                              final files = await _generateIntersection(
                                context,
                                name,
                              );

                              if (dialogShown && nav.canPop()) {
                                nav.pop();
                                dialogShown = false;
                              }

                              if (files == null || files.length < 2) return;

                              await Share.shareXFiles([
                                XFile(files[0].path),
                                XFile(files[1].path),
                              ], subject: 'Intersecciones geométricas');

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Archivos KMZ y PDF generados y compartidos correctamente',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (dialogShown && nav.canPop()) {
                                nav.pop();
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.analytics,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Generar Superposición',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Se analizarán ${layerStates.values.where((v) => v == true).length} capas activas',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<File> _generateIntersectionPdfReport(
    Map<String, Map<String, dynamic>> allResults,
    List<SavedDrawingLayer> activeDrawingLayers,
    List<String> activeThematicLayers, {
    required String queryCode,
  }) async {
    final pdf = pw.Document();
    final font = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final ttf = pw.Font.ttf(font);
    final logoData = await rootBundle.load('assets/icon/icon.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: ttf),
          pageFormat: PdfPageFormat.a4,
          buildBackground: (context) => pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 1, color: PdfColors.grey300),
            ),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    'REPORTE DE RESULTADOS DE SUPERPOSICIÓN',
                    style: pw.TextStyle(fontSize: 24, font: ttf),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Fecha: ${DateTime.now().toString().split('.')[0]}',
                  style: pw.TextStyle(font: ttf),
                ),
                pw.Text('Datum: WGS84 – UTM', style: pw.TextStyle(font: ttf)),
                pw.Text(
                  'Código de Consulta: $queryCode',
                  style: pw.TextStyle(font: ttf),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'CAPAS DE DIBUJO:',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                _buildDrawingLayersTable(activeDrawingLayers, ttf),
                pw.SizedBox(height: 20),
                pw.Text(
                  'CAPAS TEMÁTICAS EN CONSULTA:',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                _buildThematicLayersTable(activeThematicLayers, ttf),
                pw.SizedBox(height: 20),
                pw.Text(
                  'RESULTADOS DE SUPERPOSICION:',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                _buildIntersectionResultsTable(allResults, ttf),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    'VISUALIZACIÓN DE INTERSECCIONES',
                    style: pw.TextStyle(fontSize: 24, font: ttf),
                  ),
                ),
                pw.SizedBox(height: 20),
                for (var entry in allResults.entries) ...[
                  pw.Text(
                    'Capa: ${entry.key.replaceAll('sp_', '').replaceAll('_', ' ')}',
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  _buildIntersectionVisualization(
                    entry.value,
                    Color(
                      int.parse(
                        '0xFF${_getColorForLayer(entry.key).substring(2)}',
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 20),
                ],
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Fecha de Reporte: ${DateTime.now().toString().split('.')[0]}',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Usuario: Admin 1',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Autor: InGeo V1-2025',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Center(child: pw.Image(logoImage, width: 240)),
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.Text(
                    'Transforma tu celular en un GPS inteligente y analiza la viabilidad geográfica de tus proyectos en tiempo real y con datos de campo',
                    style: pw.TextStyle(font: ttf, fontSize: 12),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/interseccion_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  pw.Widget _buildIntersectionVisualization(dynamic geoJson, Color layerColor) {
    try {
      final features = geoJson['features'] as List<dynamic>;
      final polygons = <List<LatLng>>[];
      final lines = <List<LatLng>>[];
      final pts = <LatLng>[];
      for (var feature in features) {
        final geometry = feature['geometry'];
        final geomType = geometry['type'] as String;
        final coords = geometry['coordinates'];
        if (geomType == 'Polygon') {
          final outerRing = (coords[0] as List<dynamic>).map((coord) {
            return LatLng(
              (coord[1] is int
                  ? (coord[1] as int).toDouble()
                  : coord[1] as double),
              (coord[0] is int
                  ? (coord[0] as int).toDouble()
                  : coord[0] as double),
            );
          }).toList();
          polygons.add(outerRing);
        } else if (geomType == 'MultiPolygon') {
          for (var polygon in coords) {
            final outerRing = (polygon[0] as List<dynamic>).map((coord) {
              return LatLng(
                (coord[1] is int
                    ? (coord[1] as int).toDouble()
                    : coord[1] as double),
                (coord[0] is int
                    ? (coord[0] as int).toDouble()
                    : coord[0] as double),
              );
            }).toList();
            polygons.add(outerRing);
          }
        } else if (geomType == 'LineString') {
          final line = (coords as List<dynamic>).map((c) {
            return LatLng(
              (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
              (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
            );
          }).toList();
          lines.add(line);
        } else if (geomType == 'MultiLineString') {
          for (var lineCoords in (coords as List<dynamic>)) {
            final line = (lineCoords as List<dynamic>).map((c) {
              return LatLng(
                (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
                (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
              );
            }).toList();
            lines.add(line);
          }
        } else if (geomType == 'Point') {
          final lon = (coords as List<dynamic>)[0];
          final lat = (coords as List<dynamic>)[1];
          pts.add(
            LatLng(
              (lat is int ? lat.toDouble() : lat as double),
              (lon is int ? lon.toDouble() : lon as double),
            ),
          );
        }
      }
      if (polygons.isEmpty && lines.isEmpty && pts.isEmpty) {
        return pw.Container(
          height: 100,
          alignment: pw.Alignment.center,
          child: pw.Text('No hay geometrías para visualizar'),
        );
      }

      final all = <LatLng>[];
      for (var p in polygons) {
        all.addAll(p);
      }
      for (var l in lines) {
        all.addAll(l);
      }
      all.addAll(pts);
      double minLat = double.infinity, maxLat = -double.infinity;
      double minLng = double.infinity, maxLng = -double.infinity;
      for (var point in all) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
      // Add padding
      final latRange = (maxLat - minLat) == 0 ? 0.001 : (maxLat - minLat);
      final lngRange = (maxLng - minLng) == 0 ? 0.001 : (maxLng - minLng);

      // Pad bounds by 10%
      final paddedMinLat = minLat - latRange * 0.05;
      final paddedMinLng = minLng - lngRange * 0.05;
      final paddedLatRange = latRange * 1.1;
      final paddedLngRange = lngRange * 1.1;

      final pdfColor = PdfColor(
        layerColor.red / 255,
        layerColor.green / 255,
        layerColor.blue / 255,
        0.7,
      );

      return pw.Container(
        height: 250,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey),
        ),
        child: pw.CustomPaint(
          size: const PdfPoint(400, 250),
          painter: (context, size) {
            // Calculate scale to preserve aspect ratio
            final double dataAspect = paddedLngRange / paddedLatRange;
            final double canvasAspect = size.x / size.y;

            double drawWidth, drawHeight;
            if (dataAspect > canvasAspect) {
              drawWidth = size.x;
              drawHeight = size.x / dataAspect;
            } else {
              drawHeight = size.y;
              drawWidth = size.y * dataAspect;
            }

            final double offsetX = (size.x - drawWidth) / 2;
            final double offsetY = (size.y - drawHeight) / 2;

            PdfPoint project(LatLng p) {
              final xNorm = (p.longitude - paddedMinLng) / paddedLngRange;
              final yNorm = (p.latitude - paddedMinLat) / paddedLatRange;
              // Map to standard Cartesian (Bottom-Left origin)
              return PdfPoint(
                offsetX + xNorm * drawWidth,
                offsetY + yNorm * drawHeight,
              );
            }

            for (var polygon in polygons) {
              if (polygon.length < 3) continue;
              final points = polygon.map(project).toList();
              context.setFillColor(pdfColor);
              context.setStrokeColor(PdfColors.black);
              context.setLineWidth(0.5);
              context.moveTo(points[0].x, points[0].y);
              for (var i = 1; i < points.length; i++) {
                context.lineTo(points[i].x, points[i].y);
              }
              context.closePath();
              context.fillAndStrokePath();
            }
            context.setStrokeColor(pdfColor);
            context.setLineWidth(1.2);
            for (var line in lines) {
              if (line.length < 2) continue;
              final points = line.map(project).toList();
              context.moveTo(points[0].x, points[0].y);
              for (var i = 1; i < points.length; i++) {
                context.lineTo(points[i].x, points[i].y);
              }
              context.strokePath();
            }
            context.setFillColor(pdfColor);
            for (var p in pts) {
              final pt = project(p);
              context.drawEllipse(pt.x - 3, pt.y - 3, 6, 6);
              context.fillPath();
            }

            // Draw North Arrow (Top Right)
            final arrowX = size.x - 25;
            final arrowY = size.y - 25;

            context.setStrokeColor(PdfColors.black);
            context.setLineWidth(1.5);

            // Vertical line
            context.moveTo(arrowX, arrowY - 15);
            context.lineTo(arrowX, arrowY + 15);
            context.strokePath();

            // Arrow head
            context.moveTo(arrowX - 4, arrowY + 8);
            context.lineTo(arrowX, arrowY + 15);
            context.lineTo(arrowX + 4, arrowY + 8);
            context.strokePath();

            // 'N' letter (vector drawing to avoid font dependency)
            const nSize = 8.0;
            final nY =
                arrowY - 20; // Above the arrow? Or below? Let's put 'N' on top.
            // Actually, usually N is on top of arrow.
            // Let's draw N above the arrow tip
            final nTop = arrowY + 24;

            // Draw N at (arrowX - 4, nTop)
            context.setLineWidth(1.0);
            context.moveTo(arrowX - 3, nTop - 6);
            context.lineTo(arrowX - 3, nTop);
            context.lineTo(arrowX + 3, nTop - 6);
            context.lineTo(arrowX + 3, nTop);
            context.strokePath();
          },
        ),
      );
    } catch (e) {
      return pw.Container(
        height: 100,
        alignment: pw.Alignment.center,
        child: pw.Text('Error al visualizar: ${e.toString()}'),
      );
    }
  }

  pw.Widget _buildDrawingLayersTable(
    List<SavedDrawingLayer> layers,
    pw.Font font,
  ) {
    pw.Widget _coordsCell(SavedDrawingLayer layer) {
      if (layer.lines.isNotEmpty) {
        final pts = layer.lines.first.polyline.points;
        if (pts.isNotEmpty) {
          final startUtm = _latLngToUtmString(pts.first);
          final endUtm = _latLngToUtmString(pts.last);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  text: 'Inicio: ',
                  style: pw.TextStyle(
                    font: font,
                    color: PdfColors.black,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  children: [
                    pw.TextSpan(
                      text: startUtm,
                      style: pw.TextStyle(font: font),
                    ),
                  ],
                ),
              ),
              pw.RichText(
                text: pw.TextSpan(
                  text: 'Fin: ',
                  style: pw.TextStyle(
                    font: font,
                    color: PdfColors.black,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  children: [
                    pw.TextSpan(
                      text: endUtm,
                      style: pw.TextStyle(font: font),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
      } else if (layer.polygons.isNotEmpty) {
        final centroid = _calculatePolygonCentroid(
          layer.polygons.first.polygon.points,
        );
        final utm = _latLngToUtmString(centroid);
        return pw.RichText(
          text: pw.TextSpan(
            text: 'Centroide: ',
            style: pw.TextStyle(
              font: font,
              color: PdfColors.black,
              fontWeight: pw.FontWeight.bold,
            ),
            children: [
              pw.TextSpan(
                text: utm,
                style: pw.TextStyle(font: font),
              ),
            ],
          ),
        );
      } else if (layer.points.isNotEmpty) {
        final utm = _latLngToUtmString(layer.points.first.marker.point);
        return pw.RichText(
          text: pw.TextSpan(
            text: 'Punto: ',
            style: pw.TextStyle(
              font: font,
              color: PdfColors.black,
              fontWeight: pw.FontWeight.bold,
            ),
            children: [
              pw.TextSpan(
                text: utm,
                style: pw.TextStyle(font: font),
              ),
            ],
          ),
        );
      }
      return pw.Text('-', style: pw.TextStyle(font: font));
    }

    pw.Widget _measureCell(SavedDrawingLayer layer) {
      if (layer.lines.isNotEmpty) {
        final pts = layer.lines.first.polyline.points;
        final meters = _calculateLineLengthMeters(pts);
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${(meters / 1000).toStringAsFixed(2)} km',
              style: pw.TextStyle(font: font),
            ),
            pw.Text(
              '${meters.toStringAsFixed(0)} m',
              style: pw.TextStyle(font: font),
            ),
          ],
        );
      } else if (layer.polygons.isNotEmpty) {
        final area = _calculatePolygonAreaMeters2(
          layer.polygons.first.polygon.points,
        );
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${(area / 10000).toStringAsFixed(2)} Ha',
              style: pw.TextStyle(font: font),
            ),
            pw.Text(
              '${_formatThousands(area.round())} m²',
              style: pw.TextStyle(font: font),
            ),
          ],
        );
      }
      return pw.Text('-', style: pw.TextStyle(font: font));
    }

    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Nombre',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Coordenadas WGS84 - UTM',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Medida',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Puntos',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Líneas',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Polígonos',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        for (var layer in layers)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(layer.name, style: pw.TextStyle(font: font)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: _coordsCell(layer),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: _measureCell(layer),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  layer.points.length.toString(),
                  style: pw.TextStyle(font: font),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  layer.lines.length.toString(),
                  style: pw.TextStyle(font: font),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  layer.polygons.length.toString(),
                  style: pw.TextStyle(font: font),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _latLngToUtmString(LatLng p) {
    final utm = UTM.fromLatLon(lat: p.latitude, lon: p.longitude);
    return '${utm.easting.round()}E ${utm.northing.round()}N ${utm.zoneNumber}${utm.zoneLetter}';
  }

  double _calculateLineLengthMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    final d = Distance();
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  double _calculatePolygonAreaMeters2(List<LatLng> points) {
    if (points.length < 3) return 0;

    try {
      // Convertir todos los puntos a UTM
      final utmPoints = points
          .map((p) => UTM.fromLatLon(lat: p.latitude, lon: p.longitude))
          .toList();

      double area = 0;
      for (int i = 0; i < utmPoints.length; i++) {
        final p1 = utmPoints[i];
        final p2 = utmPoints[(i + 1) % utmPoints.length];
        area += (p1.easting * p2.northing) - (p2.easting * p1.northing);
      }
      return area.abs() / 2.0;
    } catch (e) {
      debugPrint('Error calculating area: $e');
      return 0;
    }
  }

  String _formatThousands(int n) {
    final s = n.toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
  }

  LatLng _calculatePolygonCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double lat = 0, lon = 0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  pw.Widget _buildThematicLayersTable(List<String> layerIds, pw.Font font) {
    String _groupForLayer(String id) {
      for (final g in layerGroups) {
        for (final item in g.items) {
          if (item.layerId == id) return g.title;
        }
      }
      return '';
    }

    String _nameForLayer(String id) {
      for (final g in layerGroups) {
        for (final item in g.items) {
          if (item.layerId == id) return item.title;
        }
      }
      return id.replaceAll('sp_', '').replaceAll('_', ' ');
    }

    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Nombre de capa',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'Grupo',
                style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        for (var layerId in layerIds)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  _nameForLayer(layerId),
                  style: pw.TextStyle(font: font),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  _groupForLayer(layerId),
                  style: pw.TextStyle(font: font),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _buildIntersectionResultsTable(
    Map<String, Map<String, dynamic>> results,
    pw.Font font,
  ) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'Inputs',
              style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'Descripción',
              style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'Área en Superposición',
              style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    ];

    for (var entry in results.entries) {
      final feats = (entry.value['features'] as List?) ?? const <dynamic>[];
      if (feats.isEmpty) continue;

      final byInput = <String, List<dynamic>>{};
      for (final f in feats) {
        final props = ((f as Map)['properties'] as Map?) ?? {};
        final input1 = (props['__input1']?.toString() ?? '').trim();
        final key = input1.isNotEmpty ? input1 : 'Dibujo';
        byInput.putIfAbsent(key, () => <dynamic>[]).add(f);
      }

      for (final g in byInput.entries) {
        bool hasPolygon = false;
        bool hasLine = false;
        bool hasPoint = false;
        for (final f in g.value) {
          final geom = (f as Map)['geometry'] as Map?;
          final type = (geom?['type'] ?? '').toString();
          if (type == 'Polygon' || type == 'MultiPolygon') hasPolygon = true;
          if (type == 'LineString' || type == 'MultiLineString') hasLine = true;
          if (type == 'Point' || type == 'MultiPoint') hasPoint = true;
        }

        var input1Label = g.key;
        if (hasPoint && !hasPolygon && !hasLine) {
          final lower = input1Label.toLowerCase();
          int cut = -1;
          final idxNl = input1Label.indexOf('\n');
          if (idxNl >= 0) cut = idxNl;
          final idxCoord = lower.indexOf('coordenadas');
          if (idxCoord >= 0) {
            cut = cut == -1 ? idxCoord : math.min(cut, idxCoord);
          }
          if (cut > 0) {
            input1Label = input1Label.substring(0, cut).trim();
          }
        }

        final groupFc = {'type': 'FeatureCollection', 'features': g.value};
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  'Input 1: $input1Label\nInput 2: ${entry.key.replaceAll('sp_', '').replaceAll('_', ' ')}',
                  style: pw.TextStyle(font: font),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  _buildIntersectionDescription(entry.key, groupFc),
                  style: pw.TextStyle(font: font),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  _buildOverlapAreaCell(groupFc),
                  style: pw.TextStyle(font: font),
                ),
              ),
            ],
          ),
        );
      }
    }

    return pw.Table(border: pw.TableBorder.all(), children: rows);
  }

  String _buildIntersectionDescription(String layerId, dynamic geoJson) {
    try {
      final features = geoJson['features'] as List<dynamic>;
      if (features.isEmpty) return '';
      final firstProps = (features.first['properties'] ?? {}) as Map;

      final normalizedLayerId = layerId.trim();

      String _lineDescriptionForLayer(String id) {
        const byLayer = <String, String>{
          'sp_anp_nacionales_definidas': 'ANP Nacional Definidas',
          'sp_zonas_amortiguamiento': 'Zonas de Amortiguamiento',
          'sp_zonas_reservadas': 'Zonas Reservadas',
          'sp_areas_conservacion_regional': 'Áreas de Conservación Regional',
          'sp_areas_conservacion_privada': 'Areas de Conservación Privada',
          'sp_ecosistemas_fragiles': 'Ecosistemas Frágiles',
          'sp_bofedales_inventariados': 'Bofedales inventariados',
          'sp_bosques_secos': 'Bosques Secos',
          'sp_sigda_declarados': 'Declarados',
          'sp_sigda_delimitados': 'Delimitados',
          'sp_sigda_qhapaq_nan': 'Qhapaqñan',
          'sp_puntos_geodesicos': 'Peligros Geológicos',
          'sp_zonas_criticas': 'Zonas críticas',
        };
        final v = byLayer[id.trim()];
        if (v != null && v.trim().isNotEmpty) return v;
        for (final g in layerGroups) {
          for (final item in g.items) {
            if (item.layerId.trim() == id.trim()) return item.title;
          }
        }
        return id.replaceAll('sp_', '').replaceAll('_', ' ');
      }

      bool hasPolygon = false;
      bool hasLine = false;
      for (final f in features) {
        final g = (f as Map)['geometry'] as Map?;
        final type = (g?['type'] ?? '').toString();
        if (type == 'Polygon' || type == 'MultiPolygon') hasPolygon = true;
        if (type == 'LineString' || type == 'MultiLineString') hasLine = true;
      }

      if (hasLine && !hasPolygon) {
        return _lineDescriptionForLayer(normalizedLayerId);
      }

      const layerFields = <String, List<String>>{
        'sp_anp_nacionales_definidas': ['ANP_Nacion'],
        'sp_zonas_amortiguamiento': ['ZA_ANP'],
        'sp_zonas_reservadas': ['zr_nomb'],
        'sp_areas_conservacion_regional': ['acr_nomb'],
        'sp_areas_conservacion_privada': ['acp_nomb'],
        'sp_ecosistemas_fragiles': ['NOMEF'],
        'sp_bofedales_inventariados': ['NOMEF'],
        'sp_bosques_secos': ['NOMEF'],
        'sp_sigda_declarados': ['nombre_map'],
        'sp_sigda_delimitados': ['nomb_map'],
        'sp_sigda_qhapaq_nan': ['d_camclasv'],
        'sp_puntos_geodesicos': ['PELIGRO_ES'],
        'sp_zonas_criticas': ['PELIGRO_ES'],
      };

      const layerFallback = <String, String>{
        'sp_bofedales_inventariados': 'Bofedal INAIGEM',
        'sp_bosques_secos': 'Bosques Secos',
        'sp_zonas_criticas': 'Zonas Criticas',
      };

      String _valueForKey(Map props, String key) {
        final direct = props[key];
        if (direct != null) return direct.toString();
        final target = key.toLowerCase();
        for (final e in props.entries) {
          if (e.key.toString().toLowerCase() == target) {
            return (e.value ?? '').toString();
          }
        }
        return '';
      }

      final keys = layerFields[normalizedLayerId] ?? const <String>[];
      for (final k in keys) {
        final v = _valueForKey(firstProps, k).trim();
        if (v.isNotEmpty) return v;
      }

      final fb = layerFallback[normalizedLayerId];
      if (fb != null && fb.trim().isNotEmpty) return fb;

      final name = (firstProps['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;

      for (final entry in firstProps.entries) {
        final k = entry.key.toString().toLowerCase();
        final v = entry.value?.toString().trim() ?? '';
        if (v.isEmpty) continue;
        if (k.contains('name') || k.contains('nombre')) return v;
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  String _buildOverlapAreaCell(dynamic geoJson) {
    try {
      final features = geoJson['features'] as List<dynamic>;
      if (features.isEmpty) return '';
      bool hasPolygon = false;
      bool hasLine = false;
      bool hasPoint = false;
      for (var f in features) {
        final g = f['geometry'];
        final type = g['type'] as String;
        if (type == 'Polygon' || type == 'MultiPolygon') hasPolygon = true;
        if (type == 'LineString' || type == 'MultiLineString') hasLine = true;
        if (type == 'Point' || type == 'MultiPoint') hasPoint = true;
      }
      if (hasPoint && !hasPolygon && !hasLine) {
        return 'Si / No';
      }
      final areaStr = _calculateTotalArea(geoJson);
      final lengthStr = _calculateTotalLength(geoJson);
      if (hasLine && !hasPolygon) {
        final len = double.tryParse(lengthStr) ?? 0.0;
        final km = len / 1000.0;
        return '${len.toStringAsFixed(2)} m\n${km.toStringAsFixed(4)} Km';
      }
      if (hasPolygon) {
        final area = double.tryParse(areaStr) ?? 0.0;
        final ha = area / 10000.0;
        final formattedArea = area
            .toStringAsFixed(0)
            .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
        return '${formattedArea} m2\n${ha.toStringAsFixed(4)} Ha';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  String _getLayerType(String layerId) {
    if (layerId.startsWith('saved_layer_')) return 'Dibujo';
    if (layerId.startsWith('wms_layer_')) return 'WMS';
    if (layerId.startsWith('external_layer_')) return 'Externa';
    if (layerId.startsWith('sp_')) return 'Temática';
    return 'Desconocido';
  }

  String _calculateTotalArea(dynamic geoJson) {
    try {
      double totalArea = 0;
      final features = geoJson['features'] as List<dynamic>;
      for (var feature in features) {
        final geometry = feature['geometry'];
        final type = geometry['type'] as String;
        final coords = geometry['coordinates'];
        if (type == 'Polygon') {
          totalArea += _areaOfPolygonCoords(coords as List<dynamic>);
        } else if (type == 'MultiPolygon') {
          for (var poly in (coords as List<dynamic>)) {
            totalArea += _areaOfPolygonCoords(poly as List<dynamic>);
          }
        }
      }
      return totalArea.isFinite ? totalArea.toStringAsFixed(2) : '0.00';
    } catch (_) {
      return 'N/A';
    }
  }

  double _areaOfPolygonCoords(List<dynamic> polygon) {
    if (polygon.isEmpty) return 0.0;
    double area = 0.0;
    final outer = polygon.first as List<dynamic>;
    area += _areaOfRingMeters(outer);
    for (int i = 1; i < polygon.length; i++) {
      area -= _areaOfRingMeters(polygon[i] as List<dynamic>);
    }
    return area.abs();
  }

  double _areaOfRingMeters(List<dynamic> ring) {
    if (ring.length < 3) return 0.0;
    final List<List<double>> pts = ring.map((c) {
      final lon = (c as List<dynamic>)[0];
      final lat = c[1];
      final utm = UTM.fromLatLon(
        lat: (lat is int ? lat.toDouble() : lat as double),
        lon: (lon is int ? lon.toDouble() : lon as double),
      );
      return [utm.easting.toDouble(), utm.northing.toDouble()];
    }).toList();
    if (pts.first[0] != pts.last[0] || pts.first[1] != pts.last[1]) {
      pts.add([pts.first[0], pts.first[1]]);
    }
    double s = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      s += pts[i][0] * pts[i + 1][1] - pts[i + 1][0] * pts[i][1];
    }
    return s.abs() / 2.0;
  }

  String _calculateTotalLength(dynamic geoJson) {
    try {
      double totalLen = 0;
      final features = geoJson['features'] as List<dynamic>;
      final d = Distance();
      for (var feature in features) {
        final geometry = feature['geometry'];
        final type = geometry['type'] as String;
        final coords = geometry['coordinates'];
        if (type == 'LineString') {
          final pts = (coords as List<dynamic>).map((c) {
            final lon = (c as List<dynamic>)[0];
            final lat = c[1];
            return LatLng(
              (lat is int ? lat.toDouble() : lat as double),
              (lon is int ? lon.toDouble() : lon as double),
            );
          }).toList();
          for (int i = 0; i < pts.length - 1; i++) {
            totalLen += d.distance(pts[i], pts[i + 1]);
          }
        } else if (type == 'MultiLineString') {
          for (var line in (coords as List<dynamic>)) {
            final pts = (line as List<dynamic>).map((c) {
              final lon = (c as List<dynamic>)[0];
              final lat = c[1];
              return LatLng(
                (lat is int ? lat.toDouble() : lat as double),
                (lon is int ? lon.toDouble() : lon as double),
              );
            }).toList();
            for (int i = 0; i < pts.length - 1; i++) {
              totalLen += d.distance(pts[i], pts[i + 1]);
            }
          }
        }
      }
      return totalLen.isFinite ? totalLen.toStringAsFixed(2) : '0.00';
    } catch (_) {
      return 'N/A';
    }
  }
}
