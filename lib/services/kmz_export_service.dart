import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class KmzExportService {
  Future<File> exportToKmz(
    Map<String, Map<String, dynamic>> geoJsonResults,
    String fileName,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final archive = Archive();

    // Consolidar features duplicados
    final filtered = _consolidateFeatures(geoJsonResults);

    if (filtered.isEmpty) {
      throw Exception('No hay intersecciones para exportar');
    }

    // Generar KML
    final kmlContent = _generateKml(filtered, fileName);
    final kmlData = utf8.encode(kmlContent);
    archive.addFile(ArchiveFile('doc.kml', kmlData.length, kmlData));

    // README
    final readme = _generateReadme(filtered);
    final readmeData = utf8.encode(readme);
    archive.addFile(ArchiveFile('README.txt', readmeData.length, readmeData));

    // Codificar y guardar
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('Error al codificar KMZ');

    final file = File('${tempDir.path}/${_sanitizeFileName(fileName)}.kmz');
    await file.writeAsBytes(zipData, flush: true);
    return file;
  }

  Map<String, Map<String, dynamic>> _consolidateFeatures(
    Map<String, Map<String, dynamic>> results,
  ) {
    final filtered = <String, Map<String, dynamic>>{};

    for (final entry in results.entries) {
      final features = entry.value['features'];
      if (features is! List || features.isEmpty) continue;

      final layerKey = entry.key.trim();
      if (filtered.containsKey(layerKey)) {
        final existing = (filtered[layerKey]!['features'] as List?) ?? [];
        existing.addAll(features);
        filtered[layerKey]!['features'] = existing;
      } else {
        filtered[layerKey] = Map<String, dynamic>.from(entry.value);
      }
    }
    return filtered;
  }

  String _generateKml(
    Map<String, Map<String, dynamic>> results,
    String projectTitle,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('<Document>');
    buffer.writeln('  <name>${_escapeXml(projectTitle)}</name>');

    // Estilos compartidos
    buffer.writeln('''
    <Style id="polyStyle">
      <LineStyle><color>ff0000ff</color><width>2</width></LineStyle>
      <PolyStyle><color>7d0000ff</color><fill>1</fill><outline>1</outline></PolyStyle>
    </Style>
    <Style id="lineStyle">
      <LineStyle><color>ff0000ff</color><width>3</width></LineStyle>
    </Style>
    <Style id="pointStyle">
      <IconStyle><scale>1.0</scale></IconStyle>
      <LabelStyle><scale>0.8</scale></LabelStyle>
    </Style>
    ''');

    // Procesar cada capa
    results.forEach((layerKey, geoJson) {
      _writeLayerFolder(buffer, layerKey, geoJson);
    });

    buffer.writeln('</Document>');
    buffer.writeln('</kml>');
    return buffer.toString();
  }

  void _writeLayerFolder(
    StringBuffer buffer,
    String layerKey,
    Map<String, dynamic> geoJson,
  ) {
    final features = geoJson['features'] as List<dynamic>;
    if (features.isEmpty) return;

    final displayName = _formatLayerName(layerKey);

    buffer.writeln('  <Folder>');
    buffer.writeln('    <name>${_escapeXml(displayName)}</name>');

    // Agrupar por tipo
    final byType = <String, List<String>>{};

    for (final feature in features) {
      final geometry = feature['geometry'];
      final properties = feature['properties'] as Map<String, dynamic>? ?? {};
      final type = geometry['type'] as String;

      final cleanProps = Map<String, dynamic>.from(properties)
        ..removeWhere((k, _) => k.startsWith('__'));

      final name =
          properties['__input1']?.toString() ??
          properties['name']?.toString() ??
          'Elemento';

      final placemark = _buildPlacemark(geometry, name, cleanProps, type);

      byType.putIfAbsent(type, () => []).add(placemark);
    }

    // Escribir subcarpetas
    _writeTypeFolder(
      buffer,
      'Puntos',
      byType['Point'] ?? byType['MultiPoint'] ?? [],
    );
    _writeTypeFolder(
      buffer,
      'Líneas',
      byType['LineString'] ?? byType['MultiLineString'] ?? [],
    );
    _writeTypeFolder(
      buffer,
      'Polígonos',
      byType['Polygon'] ?? byType['MultiPolygon'] ?? [],
    );

    buffer.writeln('  </Folder>');
  }

  void _writeTypeFolder(
    StringBuffer buffer,
    String name,
    List<String> placemarks,
  ) {
    if (placemarks.isEmpty) return;
    buffer.writeln('    <Folder><name>$name</name>');
    buffer.writeln(placemarks.join('\\n'));
    buffer.writeln('    </Folder>');
  }

  String _buildPlacemark(
    Map<String, dynamic> geometry,
    String name,
    Map<String, dynamic> properties,
    String type,
  ) {
    String kmlGeom;
    String styleId;

    switch (type) {
      case 'Point':
        styleId = '#pointStyle';
        final coords = geometry['coordinates'] as List;
        kmlGeom =
            '<Point><coordinates>${coords[0]},${coords[1]},0</coordinates></Point>';
        break;
      case 'LineString':
        styleId = '#lineStyle';
        kmlGeom =
            '<LineString><coordinates>${_coordsToKml(geometry['coordinates'])}</coordinates></LineString>';
        break;
      case 'MultiLineString':
        styleId = '#lineStyle';
        final lines = (geometry['coordinates'] as List)
            .map(
              (l) =>
                  '<LineString><coordinates>${_coordsToKml(l)}</coordinates></LineString>',
            )
            .join('');
        kmlGeom = '<MultiGeometry>$lines</MultiGeometry>';
        break;
      case 'Polygon':
        styleId = '#polyStyle';
        final ring = geometry['coordinates'][0];
        kmlGeom =
            '<Polygon><outerBoundaryIs><LinearRing><coordinates>${_coordsToKml(ring)}</coordinates></LinearRing></outerBoundaryIs></Polygon>';
        break;
      case 'MultiPolygon':
        styleId = '#polyStyle';
        final polys = (geometry['coordinates'] as List)
            .map((p) {
              final ring = p[0];
              return '<Polygon><outerBoundaryIs><LinearRing><coordinates>${_coordsToKml(ring)}</coordinates></LinearRing></outerBoundaryIs></Polygon>';
            })
            .join('');
        kmlGeom = '<MultiGeometry>$polys</MultiGeometry>';
        break;
      default:
        return '';
    }

    final extendedData = StringBuffer('<ExtendedData>');
    properties.forEach((k, v) {
      extendedData.write(
        '<Data name=\"${_escapeXml(k)}\"><value>${_escapeXml(v.toString())}</value></Data>',
      );
    });
    extendedData.write('</ExtendedData>');

    final description = properties.entries
        .map((e) => '<b>${e.key}:</b> ${e.value}')
        .join('<br/>');

    return '''
      <Placemark>
        <name>${_escapeXml(name)}</name>
        <description><![CDATA[$description]]></description>
        <styleUrl>$styleId</styleUrl>
        $extendedData
        $kmlGeom
      </Placemark>
    ''';
  }

  String _coordsToKml(List<dynamic> coords) {
    return coords.map((c) => '${c[0]},${c[1]},0').join(' ');
  }

  String _formatLayerName(String layerKey) {
    return layerKey
        .replaceAll('sp_anp_nacionales_definidas', 'ANP Nacionales')
        .replaceAll('sp_zonas_amortiguamiento', 'Zonas de Amortiguamiento')
        .replaceAll('sp_', '')
        .replaceAll('_', ' ')
        .toUpperCase();
  }

  String _generateReadme(Map<String, Map<String, dynamic>> results) {
    final buffer = StringBuffer();
    buffer.writeln('INTERSECCIONES GEOMÉTRICAS - REPORTE DE EXPORTACIÓN');
    buffer.writeln('=' * 50);
    buffer.writeln('Fecha: ${DateTime.now()}');
    buffer.writeln('');
    buffer.writeln('RESUMEN DE DATOS:');
    results.forEach((layer, data) {
      final count = (data['features'] as List).length;
      buffer.writeln('- $layer: $count elementos');
    });
    return buffer.toString();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
