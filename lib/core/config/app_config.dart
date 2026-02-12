import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');
  }

  // Servidor
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://glgisclienteb.ideasg.org';

  // Identificadores
  static String get idSistema => dotenv.env['ID_SISTEMA'] ?? '43';
  static String get idCliente => dotenv.env['ID_CLIENTE'] ?? '95';

  static String get geoserverUrl =>
      dotenv.env['GEOSERVER_URL'] ?? 'http://localhost:8080/geoserver';
  static String get geoserverUser => dotenv.env['GEOSERVER_USER'] ?? '';
  static String get geoserverPass => dotenv.env['GEOSERVER_PASS'] ?? '';
  static String get workspace => dotenv.env['WORKSPACE'] ?? 'ingeo';
  static String get defaultSrs => dotenv.env['DEFAULT_SRS'] ?? 'EPSG:4326';
}
