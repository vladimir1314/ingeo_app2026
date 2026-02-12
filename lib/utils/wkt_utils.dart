import 'package:latlong2/latlong.dart';

class WktUtils {
  static String polygonToWkt(List<LatLng> points) {
    if (points.isEmpty) return '';

    final coords = points.map((p) => '${p.longitude} ${p.latitude}').join(',');
    // Cerrar polígono si es necesario
    final first = points.first;
    final last = points.last;
    final closed =
        (first.latitude == last.latitude && first.longitude == last.longitude)
        ? coords
        : '$coords,${first.longitude} ${first.latitude}';

    return 'POLYGON(($closed))';
  }

  static String multiPolygonToWkt(List<List<LatLng>> polygons) {
    final polyStrings = polygons
        .map((points) {
          final coords = points
              .map((p) => '${p.longitude} ${p.latitude}')
              .join(',');
          final first = points.first;
          final last = points.last;
          final closed =
              (first.latitude == last.latitude &&
                  first.longitude == last.longitude)
              ? coords
              : '$coords,${first.longitude} ${first.latitude}';
          return '(($closed))';
        })
        .join(',');

    return 'MULTIPOLYGON($polyStrings)';
  }

  static String lineToWkt(List<LatLng> points) {
    if (points.length < 2) return '';
    final coords = points.map((p) => '${p.longitude} ${p.latitude}').join(',');
    return 'LINESTRING($coords)';
  }

  static String multiLineToWkt(List<List<LatLng>> lines) {
    final lineStrings = lines
        .map((points) {
          final coords = points
              .map((p) => '${p.longitude} ${p.latitude}')
              .join(',');
          return '($coords)';
        })
        .join(',');
    return 'MULTILINESTRING($lineStrings)';
  }

  static String pointToWkt(LatLng point) {
    return 'POINT(${point.longitude} ${point.latitude})';
  }

  static String multiPointToWkt(List<LatLng> points) {
    final coords = points
        .map((p) => '(${p.longitude} ${p.latitude})')
        .join(',');
    return 'MULTIPOINT($coords)';
  }

  static bool isValidWkt(String wkt) {
    if (wkt.isEmpty) return false;
    final validTypes = [
      'POINT',
      'LINESTRING',
      'POLYGON',
      'MULTIPOINT',
      'MULTILINESTRING',
      'MULTIPOLYGON',
      'GEOMETRYCOLLECTION',
    ];
    return validTypes.any((type) => wkt.startsWith(type));
  }
}
