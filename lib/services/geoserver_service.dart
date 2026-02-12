import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ingeo_app/core/config/geoserver_config.dart';
import 'package:pool/pool.dart';

class GeoserverService {
  final http.Client _client;
  final Pool _requestPool;

  GeoserverService({http.Client? client})
    : _client = client ?? http.Client(),
      _requestPool = Pool(5); // Máximo 5 requests concurrentes

  void dispose() {
    _client.close();
  }

  /// Ejecuta operación WPS gs:Clip para recortar geometrías
  Future<Map<String, dynamic>?> executeWpsClip({
    required String layerName,
    required String wktGeometry,
    int retries = 2,
  }) async {
    return _requestPool.withResource(() async {
      final url = Uri.parse(GeoserverConfig.wpsEndpoint);

      final xml =
          '''<?xml version="1.0" encoding="UTF-8"?>
<wps:Execute version="1.0.0" service="WPS"
  xmlns:wps="http://www.opengis.net/wps/1.0.0"
  xmlns:ows="http://www.opengis.net/ows/1.1"
  xmlns:gml="http://www.opengis.net/gml">
  <ows:Identifier>gs:Clip</ows:Identifier>
  <wps:DataInputs>
    <wps:Input>
      <ows:Identifier>features</ows:Identifier>
      <wps:Reference mimeType="text/xml" xlink:href="http://geoserver/wfs" method="POST">
        <wps:Body>
          <wfs:GetFeature service="WFS" version="1.0.0" outputFormat="GML2">
            <wfs:Query typeName="${GeoserverConfig.workspace}:$layerName"/>
          </wfs:GetFeature>
        </wps:Body>
      </wps:Reference>
    </wps:Input>
    <wps:Input>
      <ows:Identifier>clip</ows:Identifier>
      <wps:Data>
        <wps:ComplexData mimeType="application/wkt"><![CDATA[$wktGeometry]]></wps:ComplexData>
      </wps:Data>
    </wps:Input>
  </wps:DataInputs>
  <wps:ResponseForm>
    <wps:RawDataOutput mimeType="application/json">
      <ows:Identifier>result</ows:Identifier>
    </wps:RawDataOutput>
  </wps:ResponseForm>
</wps:Execute>''';

      for (var attempt = 0; attempt <= retries; attempt++) {
        try {
          final response = await _client
              .post(
                url,
                headers: {
                  ...GeoserverConfig.authHeaders,
                  'Content-Type': 'application/xml',
                },
                body: xml,
              )
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 200) {
            final contentType = response.headers['content-type'] ?? '';
            if (contentType.contains('json') ||
                response.body.trim().startsWith('{')) {
              return json.decode(response.body) as Map<String, dynamic>;
            }
          }

          if (attempt < retries) {
            await Future.delayed(Duration(seconds: attempt + 1));
          }
        } on TimeoutException {
          if (attempt == retries) rethrow;
        }
      }
      return null;
    });
  }

  /// Consulta WFS con filtro espacial
  Future<List<dynamic>> queryWfs({
    required String layerName,
    required String wktGeometry,
    String operation = 'INTERSECTS',
    String? geometryAttribute,
  }) async {
    return _requestPool.withResource(() async {
      final geomAttr =
          geometryAttribute ?? await getGeometryAttribute(layerName) ?? 'geom';
      final cqlFilter = '$operation($geomAttr,SRID=4326;$wktGeometry)';

      final url = Uri.parse(GeoserverConfig.wfsEndpoint).replace(
        queryParameters: {
          'service': 'WFS',
          'version': '2.0.0',
          'request': 'GetFeature',
          'typeName': '${GeoserverConfig.workspace}:$layerName',
          'outputFormat': 'application/json',
          'srsName': GeoserverConfig.defaultSrs,
          'CQL_FILTER': cqlFilter,
        },
      );

      final response = await _client
          .get(url, headers: GeoserverConfig.authHeaders)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw HttpException(
          'WFS Error ${response.statusCode}: ${response.body}',
        );
      }

      final geoJson = json.decode(response.body) as Map<String, dynamic>;
      return geoJson['features'] as List<dynamic>? ?? [];
    });
  }

  /// Obtiene nombre del atributo de geometría (con caché)
  final Map<String, String> _geometryAttrCache = {};

  Future<String?> getGeometryAttribute(String layerName) async {
    if (_geometryAttrCache.containsKey(layerName)) {
      return _geometryAttrCache[layerName];
    }

    try {
      final url = Uri.parse(GeoserverConfig.wfsEndpoint).replace(
        queryParameters: {
          'service': 'WFS',
          'version': '1.0.0',
          'request': 'DescribeFeatureType',
          'typeName': '${GeoserverConfig.workspace}:$layerName',
        },
      );

      final response = await _client.get(
        url,
        headers: GeoserverConfig.authHeaders,
      );

      if (response.statusCode == 200) {
        final match = RegExp(
          r'name="(\\w+)"\\s+type="gml:',
        ).firstMatch(response.body);
        final attr = match?.group(1);
        if (attr != null) {
          _geometryAttrCache[layerName] = attr;
        }
        return attr;
      }
    } catch (e) {
      debugPrint('Error getting geometry attribute: $e');
    }
    return null;
  }

  /// JTS:intersection para recorte de líneas
  Future<Map<String, dynamic>?> executeJtsIntersection({
    required String wktLine,
    required String wktPolygon,
  }) async {
    return _requestPool.withResource(() async {
      final url = Uri.parse(GeoserverConfig.wpsEndpoint);

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
        <wps:ComplexData mimeType="application/wkt"><![CDATA[$wktPolygon]]></wps:ComplexData>
      </wps:Data>
    </wps:Input>
  </wps:DataInputs>
  <wps:ResponseForm>
    <wps:RawDataOutput mimeType="application/wkt">
      <ows:Identifier>result</ows:Identifier>
    </wps:RawDataOutput>
  </wps:ResponseForm>
</wps:Execute>''';

      final response = await _client.post(
        url,
        headers: {...GeoserverConfig.authHeaders, 'Content-Type': 'text/xml'},
        body: xml,
      );

      if (response.statusCode == 200) {
        final wkt = response.body.trim();
        return _wktLineToGeoJson(wkt);
      }
      return null;
    });
  }

  Map<String, dynamic>? _wktLineToGeoJson(String wkt) {
    if (wkt.isEmpty || wkt.contains('EMPTY')) return null;

    if (wkt.startsWith('MULTILINESTRING')) {
      final inner = wkt.substring('MULTILINESTRING'.length).trim();
      final content = inner.substring(1, inner.length - 1);
      final parts = content.split('),(');
      final lines = parts.map((p) {
        final s = p.replaceAll('(', '').replaceAll(')', '');
        return s.split(',').map((pt) {
          final xy = pt.trim().split(' ');
          return [double.parse(xy[0]), double.parse(xy[1])];
        }).toList();
      }).toList();

      return {
        'type': 'Feature',
        'geometry': {'type': 'MultiLineString', 'coordinates': lines},
        'properties': {},
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
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'properties': {},
      };
    }
    return null;
  }
}
