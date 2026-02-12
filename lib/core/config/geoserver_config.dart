import 'dart:convert';

import 'package:ingeo_app/core/config/app_config.dart';

class GeoserverConfig {
  static String get workspace => AppConfig.workspace;
  static String get defaultSrs => AppConfig.defaultSrs;
  static String get baseUrl => AppConfig.geoserverUrl;
  static String get wpsEndpoint => '$baseUrl/wps';
  static String get wfsEndpoint => '$baseUrl/${AppConfig.workspace}/ows';
  static String get wmsEndpoint => '$baseUrl/${AppConfig.workspace}/wms';

  static Map<String, String> get authHeaders {
    final credentials = '${AppConfig.geoserverUser}:${AppConfig.geoserverPass}';
    final encoded = base64Encode(utf8.encode(credentials));
    return {'Authorization': 'Basic $encoded'};
  }
}
