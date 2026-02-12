import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:utm/utm.dart';
import 'package:turf/turf.dart' as turf;

class GeometryUtils {
  static final Distance _distance = Distance();

  /// Calcula distancia total de una línea en metros
  static double calculateLineLength(List<LatLng> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  /// Calcula área de polígono usando fórmula de shoelace en UTM
  static double calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0;

    try {
      // Convertir a UTM para cálculo preciso
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
      return 0;
    }
  }

  /// Calcula centroide de polígono
  static LatLng calculateCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);

    double lat = 0, lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  /// Convierte LatLng a string UTM
  static String latLngToUtmString(LatLng p) {
    final utm = UTM.fromLatLon(lat: p.latitude, lon: p.longitude);
    return '${utm.easting.round()}E ${utm.northing.round()}N ${utm.zoneNumber}${utm.zoneLetter}';
  }

  /// Verifica si punto está dentro de polígono usando Turf
  static bool pointInPolygon(LatLng point, List<List<double>> ring) {
    try {
      final pointFeature = turf.Point(
        coordinates: turf.Position.of([point.longitude, point.latitude]),
      );

      final polygonFeature = turf.Polygon(
        coordinates: [
          ring.map((c) => turf.Position.of([c[0], c[1]])).toList(),
        ],
      );

      return turf.booleanPointInPolygon(
        pointFeature.coordinates,
        polygonFeature,
      );
    } catch (e) {
      // Fallback a algoritmo ray-casting
      return _pointInPolygonRayCasting(point, ring);
    }
  }

  static bool _pointInPolygonRayCasting(LatLng p, List<List<double>> ring) {
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

  /// Formatea número con separadores de miles
  static String formatThousands(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ' ',
    );
  }

  /// Extrae anillos exteriores de features GeoJSON
  static List<List<List<double>>> extractRings(List<dynamic> features) {
    final rings = <List<List<double>>>[];

    for (final feature in features) {
      final geometry = feature['geometry'];
      final type = geometry['type'];
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
        rings.add(ring);
      } else if (type == 'MultiPolygon') {
        for (final polygon in coords) {
          final ring = (polygon[0] as List)
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

  /// Calcula intersección de segmento de línea con anillo
  static List<Map<String, dynamic>> segmentRingIntersections(
    LatLng a,
    LatLng b,
    List<List<double>> ring,
  ) {
    final intersections = <Map<String, dynamic>>[];

    for (int i = 0; i < ring.length - 1; i++) {
      final p = LatLng(ring[i][1], ring[i][0]);
      final q = LatLng(ring[i + 1][1], ring[i + 1][0]);
      final ip = _segmentIntersection(a, b, p, q);

      if (ip != null) {
        intersections.add({'t': ip['t'], 'pt': ip['pt']});
      }
    }

    intersections.sort(
      (x, y) => (x['t'] as double).compareTo(y['t'] as double),
    );
    return intersections;
  }

  static Map<String, dynamic>? _segmentIntersection(
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
}
