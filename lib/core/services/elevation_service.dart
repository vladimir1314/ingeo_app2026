import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio para obtener la altitud desde una API y cachearla localmente
class ElevationService {
  // Mapa para cachear altitudes: key = "lat,lon"
  static final Map<String, int> _altitudeCache = {};

  /// Obtiene la altitud en metros para una latitud/longitud
  static Future<int> fetchElevation(double lat, double lon) async {
    final key = "${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}";

    // Si ya está en cache, devuelve sin llamar al servidor
    if (_altitudeCache.containsKey(key)) {
      return _altitudeCache[key]!;
    }

    // Llamada a API
    final url = Uri.parse(
      'https://api.opentopodata.org/v1/srtm90m?locations=$lat,$lon',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] != null && data['results'].isNotEmpty) {
        final elevation = data['results'][0]['elevation'];
        final roundedElevation = (elevation as num).round();

        // Guardar en cache
        _altitudeCache[key] = roundedElevation;

        return roundedElevation;
      } else {
        throw Exception("No se encontró elevación");
      }
    } else {
      throw Exception("Error al obtener elevación: ${response.statusCode}");
    }
  }
}
