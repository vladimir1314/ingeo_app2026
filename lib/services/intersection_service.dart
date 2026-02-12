import 'package:flutter/foundation.dart'; // For compute
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:latlong2/latlong.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:ingeo_app/utils/wkt_utils.dart';
import 'package:ingeo_app/utils/geometry_utils.dart';
import 'package:polybool/polybool.dart' as pb; // Changed from turf to polybool
import 'geoserver_service.dart';

class IntersectionService {
  final GeoserverService _geoService;

  IntersectionService(this._geoService);

  Future<Map<String, Map<String, dynamic>>> performIntersection({
    required List<SavedDrawingLayer> drawingLayers,
    required List<String> thematicLayers,
    required Function(double) onProgress,
  }) async {
    debugPrint('Iniciando performIntersection con ${drawingLayers.length} capas de dibujo y ${thematicLayers.length} capas temáticas');
    final allResults = <String, Map<String, dynamic>>{};
    final totalSteps = drawingLayers.length * thematicLayers.length;
    int currentStep = 0;

    for (final drawingLayer in drawingLayers) {
      debugPrint('Procesando capa de dibujo: ${drawingLayer.name}');
      // Procesar polígonos
      if (drawingLayer.polygons.isNotEmpty) {
        debugPrint('  -> Procesando polígonos...');
        await _processPolygons(
          drawingLayer: drawingLayer,
          thematicLayers: thematicLayers,
          results: allResults,
          onProgress: (p) => onProgress((currentStep + p) / totalSteps),
        );
      }

      // Procesar líneas
      if (drawingLayer.lines.isNotEmpty) {
        debugPrint('  -> Procesando líneas...');
        await _processLines(
          drawingLayer: drawingLayer,
          thematicLayers: thematicLayers,
          results: allResults,
          onProgress: (p) => onProgress((currentStep + p) / totalSteps),
        );
      }

      // Procesar puntos
      if (drawingLayer.points.isNotEmpty) {
        debugPrint('  -> Procesando puntos...');
        await _processPoints(
          drawingLayer: drawingLayer,
          thematicLayers: thematicLayers,
          results: allResults,
          onProgress: (p) => onProgress((currentStep + p) / totalSteps),
        );
      }

      currentStep += thematicLayers.length;
    }
    
    debugPrint('performIntersection finalizado. Resultados: ${allResults.keys.length} capas intersectadas.');
    return allResults;
  }

  Future<void> _processPolygons({
    required SavedDrawingLayer drawingLayer,
    required List<String> thematicLayers,
    required Map<String, Map<String, dynamic>> results,
    required Function(double) onProgress,
  }) async {
    final polygons = drawingLayer.polygons
        .where((p) => p.polygon.points.isNotEmpty)
        .toList();

    if (polygons.isEmpty) return;

    // Crear MultiPolygon WKT
    final polyPoints = polygons.map((p) => p.polygon.points).toList();
    final wktMultiPolygon = WktUtils.multiPolygonToWkt(polyPoints);

    for (int i = 0; i < thematicLayers.length; i++) {
      final layerId = thematicLayers[i];
      debugPrint('    -> Verificando intersección con capa temática: $layerId');

      try {
        // Intento 1: WPS Clip
        var result = await _geoService.executeWpsClip(
          layerName: layerId,
          wktGeometry: wktMultiPolygon,
        );

        // Intento 2: WFS INTERSECTS + Recorte Cliente
        if (result == null || (result['features'] as List?)?.isEmpty == true) {
          debugPrint('      -> WPS Clip falló o vacío, intentando WFS INTERSECTS + Isolate Clip...');
          final features = await _geoService.queryWfs(
            layerName: layerId,
            wktGeometry: wktMultiPolygon,
            operation: 'INTERSECTS',
          );
          
          debugPrint('      -> WFS devolvió ${features.length} features. Iniciando recorte en isolate...');

          // Aplicar recorte (clipping) usando PolyBool en un isolate
          final drawingPolyCoords = polygons.map((p) {
            return p.polygon.points
                .map((pt) => [pt.longitude, pt.latitude])
                .toList();
          }).toList();

          final clippedFeatures = await compute(_isolateClipPolygons, {
            'features': features,
            'drawingPolygons': drawingPolyCoords,
          });
          
          debugPrint('      -> Recorte en isolate finalizado. Features resultantes: ${clippedFeatures.length}');

          result = {'type': 'FeatureCollection', 'features': clippedFeatures};
        } else {
           debugPrint('      -> WPS Clip exitoso. Features: ${(result['features'] as List).length}');
        }

        final features = result['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          _addToResults(
            results,
            layerId,
            features,
            drawingLayer.name,
            'Polígonos (${features.length})',
          );
        }
      } catch (e) {
        debugPrint('Error procesando polígonos para $layerId: $e');
      }

      onProgress((i + 1) / thematicLayers.length);
    }
  }

  // Top-level function for isolate execution
  static List<Map<String, dynamic>> _isolateClipPolygons(
    Map<String, dynamic> data,
  ) {
    final features = data['features'] as List<dynamic>;
    final drawingPolygons = (data['drawingPolygons'] as List<dynamic>)
        .map(
          (poly) => (poly as List<dynamic>)
              .map(
                (pt) =>
                    pb.Coordinate((pt as List)[0] as double, pt[1] as double),
              )
              .toList(),
        )
        .toList();

    if (drawingPolygons.isEmpty) return [];

    // 1. Combine all drawing polygons into a single geometry (Union)
    pb.Polygon combinedDrawPoly;

    // Convert the first polygon
    combinedDrawPoly = pb.Polygon(regions: [drawingPolygons[0]]);

    // Union with the rest
    for (int i = 1; i < drawingPolygons.length; i++) {
      final poly = pb.Polygon(regions: [drawingPolygons[i]]);
      combinedDrawPoly = combinedDrawPoly.union(poly);
    }

    final clipped = <Map<String, dynamic>>[];

    for (final feature in features) {
      final geometry = feature['geometry'];
      final type = geometry['type'];
      final properties = feature['properties'];

      // Convertir geometría del feature a lista de coordenadas de polígonos
      List<List<List<List<double>>>> featurePolys = [];
      
      if (type == 'Point') {
        final coord = geometry['coordinates'];
        final pt = pb.Coordinate(
          (coord[0] as num).toDouble(),
          (coord[1] as num).toDouble(),
        );
        if (_isPointInAnyPolygon(pt, drawingPolygons)) {
          clipped.add(feature);
        }
        continue;
      } else if (type == 'MultiPoint') {
        final coords = geometry['coordinates'] as List;
        final validCoords = <List<double>>[];
        for (final c in coords) {
          final pt = pb.Coordinate(
            (c[0] as num).toDouble(),
            (c[1] as num).toDouble(),
          );
          if (_isPointInAnyPolygon(pt, drawingPolygons)) {
            validCoords.add([
              (c[0] as num).toDouble(),
              (c[1] as num).toDouble(),
            ]);
          }
        }
        if (validCoords.isNotEmpty) {
          final newFeature = Map<String, dynamic>.from(feature);
          newFeature['geometry'] = {
            'type': 'MultiPoint',
            'coordinates': validCoords,
          };
          clipped.add(newFeature);
        }
        continue;
      } else if (type == 'LineString') {
        final coords =
            _extractCoordinatesStatic([geometry['coordinates']]).first;
        final clippedLines = _clipLineInPolygons(
          coords,
          combinedDrawPoly.regions,
        );
        if (clippedLines.isNotEmpty) {
          final newFeature = Map<String, dynamic>.from(feature);
          newFeature['geometry'] = {
            'type': clippedLines.length == 1 ? 'LineString' : 'MultiLineString',
            'coordinates':
                clippedLines.length == 1 ? clippedLines.first : clippedLines,
          };
          clipped.add(newFeature);
        }
        continue;
      } else if (type == 'MultiLineString') {
        final coordsList = _extractCoordinatesStatic(geometry['coordinates']);
        final allClippedLines = <List<List<double>>>[];
        for (final line in coordsList) {
          allClippedLines.addAll(
            _clipLineInPolygons(line, combinedDrawPoly.regions),
          );
        }
        if (allClippedLines.isNotEmpty) {
          final newFeature = Map<String, dynamic>.from(feature);
          newFeature['geometry'] = {
            'type': 'MultiLineString',
            'coordinates': allClippedLines,
          };
          clipped.add(newFeature);
        }
        continue;
      } else if (type == 'Polygon') {
        featurePolys.add(_extractCoordinatesStatic(geometry['coordinates']));
      } else if (type == 'MultiPolygon') {
        for (final poly in geometry['coordinates']) {
          featurePolys.add(_extractCoordinatesStatic(poly));
        }
      }

      for (final featurePolyCoords in featurePolys) {
        // Convertir feature a PolyBool polygon
        final regions1 = featurePolyCoords.map((ring) {
          return ring.map((c) => pb.Coordinate(c[0], c[1])).toList();
        }).toList();
        final poly1 = pb.Polygon(regions: regions1);

        // Intersect with combined drawing polygon
        // Optimized: Intersect once with the union of all drawing polygons
        // Instead of loop inside loop which is O(N*M)
        try {
          // We can try intersecting with the combined polygon directly
          // But if we need to know WHICH drawing polygon intersected, we might need the loop.
          // However, the original code logic seemed to output one feature per intersection
          // but didn't explicitly link it to a specific drawing polygon index in the output properties
          // except it was iterating drawingPolygons.

          // Wait, the original code iterated drawingPolygons:
          // for (final drawPoly in drawingPolygons) { ... intersect ... clipped.add(...) }
          // So if a feature intersects 2 drawing polygons, it produces 2 output features.
          // My Union optimization above changes this behavior!
          // If we want to preserve behavior, we must iterate.

          for (final drawRegion in drawingPolygons) {
            final poly2 = pb.Polygon(regions: [drawRegion]);
            final intersection = poly1.intersect(poly2);

            if (intersection.regions.isNotEmpty) {
              // Convertir resultado a GeoJSON MultiPolygon
              final multiPolyCoords = intersection.regions.map((region) {
                final ring = region
                    .map((c) => [c.x.toDouble(), c.y.toDouble()])
                    .toList();
                // Cerrar el anillo si es necesario
                if (ring.isNotEmpty &&
                    (ring.first[0] != ring.last[0] ||
                        ring.first[1] != ring.last[1])) {
                  ring.add(ring.first);
                }
                return [ring];
              }).toList();

              clipped.add({
                'type': 'Feature',
                'properties': properties,
                'geometry': {
                  'type': 'MultiPolygon',
                  'coordinates': multiPolyCoords,
                },
              });
            }
          }
        } catch (e) {
          debugPrint('Error en recorte PolyBool: $e');
        }
      }
    }
    return clipped;
  }

  static bool _isPointInAnyPolygon(
    pb.Coordinate p,
    List<List<pb.Coordinate>> polygons,
  ) {
    for (final poly in polygons) {
      if (_pointInPolygonRayCasting(p, poly)) {
        return true;
      }
    }
    return false;
  }

  static bool _pointInPolygonRayCasting(
    pb.Coordinate p,
    List<pb.Coordinate> ring,
  ) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].x;
      final yi = ring[i].y;
      final xj = ring[j].x;
      final yj = ring[j].y;

      final intersect = ((yi > p.y) != (yj > p.y)) &&
          (p.x < (xj - xi) * (p.y - yi) / (yj - yi + 1e-12) + xi);

      if (intersect) inside = !inside;
    }
    return inside;
  }

  static List<List<List<double>>> _clipLineInPolygons(
    List<List<double>> line,
    List<List<pb.Coordinate>> regions,
  ) {
    final result = <List<List<double>>>[];
    final pts = line.map((c) => LatLng(c[1], c[0])).toList();
    final rings =
        regions
            .map((r) => r.map((c) => [c.x.toDouble(), c.y.toDouble()]).toList())
            .toList();

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];

      for (final ring in rings) {
        final segments = _clipSegmentByRingStatic(a, b, ring);
        result.addAll(segments);
      }
    }

    return _mergeConnectedSegments(result);
  }

  static List<List<List<double>>> _clipSegmentByRingStatic(
    LatLng a,
    LatLng b,
    List<List<double>> ring,
  ) {
    final intersections = <Map<String, dynamic>>[];

    for (int i = 0; i < ring.length - 1; i++) {
      final p = LatLng(ring[i][1], ring[i][0]);
      final q = LatLng(ring[i + 1][1], ring[i + 1][0]);

      final x1 = a.longitude, y1 = a.latitude;
      final x2 = b.longitude, y2 = b.latitude;
      final x3 = p.longitude, y3 = p.latitude;
      final x4 = q.longitude, y4 = q.latitude;

      final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
      if (den != 0) {
        final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
        final u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / den;

        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
          final px = x1 + t * (x2 - x1);
          final py = y1 + t * (y2 - y1);
          intersections.add({'t': t, 'pt': LatLng(py, px)});
        }
      }
    }

    intersections.sort(
      (x, y) => (x['t'] as double).compareTo(y['t'] as double),
    );

    final pbRing = ring.map((c) => pb.Coordinate(c[0], c[1])).toList();
    bool isInside = _pointInPolygonRayCasting(
      pb.Coordinate(a.longitude, a.latitude),
      pbRing,
    );

    final result = <List<List<double>>>[];
    LatLng last = a;

    for (final inter in intersections) {
      final p = inter['pt'] as LatLng;
      if (isInside) {
        result.add([
          [last.longitude, last.latitude],
          [p.longitude, p.latitude],
        ]);
      }
      isInside = !isInside;
      last = p;
    }

    if (isInside) {
      result.add([
        [last.longitude, last.latitude],
        [b.longitude, b.latitude],
      ]);
    }

    return result;
  }

  static List<List<List<double>>> _mergeConnectedSegments(
    List<List<List<double>>> segments,
  ) {
    if (segments.isEmpty) return [];

    final merged = <List<List<double>>>[];
    List<List<double>> current = segments.first;

    for (int i = 1; i < segments.length; i++) {
      final next = segments[i];
      final lastPt = current.last;
      final firstPt = next.first;

      if ((lastPt[0] - firstPt[0]).abs() < 1e-9 &&
          (lastPt[1] - firstPt[1]).abs() < 1e-9) {
        current.addAll(next.sublist(1));
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  static List<List<List<double>>> _extractCoordinatesStatic(dynamic coords) {
    if (coords is List) {
      return coords
          .map((ring) {
            if (ring is List) {
              return ring.map((c) {
                if (c is List && c.length >= 2) {
                  return [
                    (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
                    (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
                  ];
                }
                return [0.0, 0.0];
              }).toList();
            }
            return <List<double>>[];
          })
          .toList()
          .cast<List<List<double>>>();
    }
    return [];
  }

  List<List<List<double>>> _extractCoordinates(dynamic coords) {
    return _extractCoordinatesStatic(coords);
  }

  Future<void> _processLines({
    required SavedDrawingLayer drawingLayer,
    required List<String> thematicLayers,
    required Map<String, Map<String, dynamic>> results,
    required Function(double) onProgress,
  }) async {
    final lines = drawingLayer.lines
        .where((l) => l.polyline.points.length >= 2)
        .toList();

    if (lines.isEmpty) return;

    final wktMultiLine = WktUtils.multiLineToWkt(
      lines.map((l) => l.polyline.points).toList(),
    );

    for (int i = 0; i < thematicLayers.length; i++) {
      final layerId = thematicLayers[i];

      try {
        // Obtener features intersectantes
        final features = await _geoService.queryWfs(
          layerName: layerId,
          wktGeometry: wktMultiLine,
          operation: 'INTERSECTS',
        );

        if (features.isEmpty) continue;

        // Extraer polígonos para recorte
        final rings = GeometryUtils.extractRings(features);
        if (rings.isEmpty) continue;

        // Recortar cada línea
        final clippedFeatures = <Map<String, dynamic>>[];
        for (final labeledLine in lines) {
          final pts = labeledLine.polyline.points;
          final segments = _clipLineByRings(pts, rings);

          if (segments.isNotEmpty) {
            clippedFeatures.add({
              'type': 'Feature',
              'properties': {
                'name': labeledLine.label,
                '__drawing_name': drawingLayer.name,
                '__input1': labeledLine.label,
              },
              'geometry': {
                'type': segments.length == 1 ? 'LineString' : 'MultiLineString',
                'coordinates': segments.length == 1 ? segments.first : segments,
              },
            });
          }
        }

        if (clippedFeatures.isNotEmpty) {
          _addToResults(
            results,
            layerId,
            clippedFeatures,
            drawingLayer.name,
            'Líneas Recortadas',
          );
        }
      } catch (e) {
        debugPrint('Error procesando líneas para $layerId: $e');
      }

      onProgress((i + 1) / thematicLayers.length);
    }
  }

  Future<void> _processPoints({
    required SavedDrawingLayer drawingLayer,
    required List<String> thematicLayers,
    required Map<String, Map<String, dynamic>> results,
    required Function(double) onProgress,
  }) async {
    final points = drawingLayer.points;
    if (points.isEmpty) return;

    final wktMultiPoint = WktUtils.multiPointToWkt(
      points.map((p) => p.marker.point).toList(),
    );

    for (int i = 0; i < thematicLayers.length; i++) {
      final layerId = thematicLayers[i];

      try {
        final features = await _geoService.queryWfs(
          layerName: layerId,
          wktGeometry: wktMultiPoint,
          operation: 'INTERSECTS',
        );

        if (features.isEmpty) continue;

        // Procesar cada punto
        for (final point in points) {
          final pt = point.marker.point;
          final matchingFeatures = features
              .where((f) => _isPointInFeature(pt, f))
              .toList();

          if (matchingFeatures.isNotEmpty) {
            final combinedProps = <String, dynamic>{};
            for (int j = 0; j < matchingFeatures.length; j++) {
              final props = matchingFeatures[j]['properties'] as Map? ?? {};
              props.forEach((k, v) {
                final key = matchingFeatures.length > 1
                    ? 'feature_${j + 1}_$k'
                    : k;
                combinedProps[key] = v;
              });
            }

            _addToResults(
              results,
              layerId,
              [
                {
                  'type': 'Feature',
                  'properties': combinedProps,
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [pt.longitude, pt.latitude],
                  },
                },
              ],
              drawingLayer.name,
              point.label,
            );
          }
        }
      } catch (e) {
        debugPrint('Error procesando puntos para $layerId: $e');
      }

      onProgress((i + 1) / thematicLayers.length);
    }
  }

  bool _isPointInFeature(LatLng pt, dynamic feature) {
    try {
      final geometry = feature['geometry'];
      final type = geometry['type'];

      if (type != 'Polygon' && type != 'MultiPolygon') return false;

      final coords = geometry['coordinates'];

      if (type == 'Polygon') {
        final ring = (coords[0] as List)
            .map(
              (c) => [
                (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
                (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
              ],
            )
            .toList();
        return GeometryUtils.pointInPolygon(pt, ring);
      } else {
        // MultiPolygon
        for (final polygon in coords) {
          final ring = (polygon[0] as List)
              .map(
                (c) => [
                  (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
                  (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
                ],
              )
              .toList();
          if (GeometryUtils.pointInPolygon(pt, ring)) return true;
        }
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  List<List<List<double>>> _clipLineByRings(
    List<LatLng> pts,
    List<List<List<double>>> rings,
  ) {
    final segments = <List<List<double>>>[];

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];

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
    final intersections = GeometryUtils.segmentRingIntersections(a, b, ring);
    final result = <List<List<double>>>[];

    bool inside = GeometryUtils.pointInPolygon(a, ring);
    LatLng last = a;

    for (final inter in intersections) {
      final p = inter['pt'] as LatLng;
      if (inside) {
        result.add([
          [last.longitude, last.latitude],
          [p.longitude, p.latitude],
        ]);
      }
      inside = !inside;
      last = p;
    }

    if (inside) {
      result.add([
        [last.longitude, last.latitude],
        [b.longitude, b.latitude],
      ]);
    }

    return result;
  }

  void _addToResults(
    Map<String, Map<String, dynamic>> allResults,
    String layerId,
    List<dynamic> newFeatures,
    String drawingName,
    String inputLabel,
  ) {
    if (newFeatures.isEmpty) return;

    allResults.putIfAbsent(
      layerId,
      () => {'type': 'FeatureCollection', 'features': <dynamic>[]},
    );

    final features = allResults[layerId]!['features'] as List;

    for (final f in newFeatures) {
      final enriched = Map<String, dynamic>.from(f as Map);
      final props = Map<String, dynamic>.from(
        (enriched['properties'] as Map?) ?? {},
      );
      props['__drawing_name'] = drawingName;
      if (!props.containsKey('__input1')) {
        props['__input1'] = inputLabel;
      }
      enriched['properties'] = props;
      features.add(enriched);
    }
  }

  SavedDrawingLayer createLayerFromResults(
    Map<String, Map<String, dynamic>> allResults,
    String fileName,
  ) {
    final lines = <LabeledPolyline>[];
    final polygons = <Polygon>[];
    final points = <LabeledMarker>[];

    allResults.forEach((layerName, geoJson) {
      final features = geoJson['features'] as List<dynamic>;
      final color = _getColorForLayer(layerName);

      for (final feature in features) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] as Map<String, dynamic>? ?? {};
        final type = geometry['type'] as String;
        final coords = geometry['coordinates'];
        final name = properties['name']?.toString() ?? 'Intersección';

        switch (type) {
          case 'Polygon':
            polygons.add(_createPolygon(coords, color, name));
            break;
          case 'MultiPolygon':
            for (final poly in coords) {
              polygons.add(_createPolygon(poly, color, name));
            }
            break;
          case 'LineString':
            lines.add(_createLine(coords, color, name));
            break;
          case 'MultiLineString':
            for (final line in coords) {
              lines.add(_createLine(line, color, name));
            }
            break;
          case 'Point':
            points.add(_createPoint(coords, name));
            break;
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
      rawGeometries: [],
      timestamp: DateTime.now(),
      attributes: {'source': 'intersection', 'fileName': fileName},
    );
  }

  Polygon _createPolygon(List<dynamic> coords, Color color, String label) {
    final points = (coords[0] as List<dynamic>)
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();

    return Polygon(
      points: points,
      color: color.withOpacity(0.4),
      borderColor: color,
      borderStrokeWidth: 2.0,
      isFilled: true,
      label: label,
    );
  }

  LabeledPolyline _createLine(List<dynamic> coords, Color color, String label) {
    final points = coords
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();

    return LabeledPolyline(
      polyline: Polyline(points: points, color: color, strokeWidth: 4.0),
      label: label,
    );
  }

  LabeledMarker _createPoint(List<dynamic> coords, String label) {
    final pt = LatLng(
      (coords[1] is int ? (coords[1] as int).toDouble() : coords[1] as double),
      (coords[0] is int ? (coords[0] as int).toDouble() : coords[0] as double),
    );

    return LabeledMarker(
      marker: Marker(
        point: pt,
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
      ),
      label: label,
      geometry: GeometryData(type: 'Point', name: label, coordinates: [pt]),
    );
  }

  Color _getColorForLayer(String layerName) {
    final colors = {
      'sp_anp_nacionales_definidas': 0xff006400,
      'sp_zonas_amortiguamiento': 0xff32cd32,
      'sp_departamentos': 0xffdc143c,
      'sp_provincias': 0xffff4500,
      'sp_distritos': 0xffff6347,
    };

    for (final entry in colors.entries) {
      if (layerName.contains(entry.key)) {
        return Color(entry.value);
      }
    }

    // Color aleatorio consistente
    final random = math.Random(layerName.hashCode);
    return Color(0xff000000 + random.nextInt(0xFFFFFF));
  }
}
