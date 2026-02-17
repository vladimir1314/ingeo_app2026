import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:utm/utm.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/utils/geometry_utils.dart';

class PdfReportService {
  final List<LayerGroup> _layerGroups;
  final Map<String, String> _layerColorMap;

  PdfReportService(this._layerGroups) : _layerColorMap = {} {
    _initializeColorMap();
  }

  void _initializeColorMap() {
    final colors = {
      // Georreferenciación
      'sp_grilla_utm_peru': 'ff808080',
      'sp_centros_poblados_inei': 'ff000000',
      // Catastro Rural
      'sp_comunidades_campesinas': 'ff8b4513',
      'sp_comunidades_nativas': 'ffcd853f',
      // Límites Políticos
      'sp_departamentos': 'ffdc143c',
      'sp_provincias': 'ffff4500',
      'sp_distritos': 'ffff6347',
      // Hidrografía
      'sp_vertientes': 'ff00008b',
      'sp_cuencas': 'ff0000ff',
      'sp_subcuencas': 'ff1e90ff',
      'sp_lagunas': 'ff00bfff',
      'sp_rios_navegables': 'ff4169e1',
      'sp_rios_quebradas': 'ff87ceeb',
      // Áreas Naturales Protegidas
      'sp_anp_nacionales_definidas': 'ff006400',
      'sp_zonas_amortiguamiento': 'ff32cd32',
      'sp_zonas_reservadas': 'ff228b22',
      'sp_areas_conservacion_regional': 'ff90ee90',
      'sp_areas_conservacion_privada': 'ff98fb98',
      // Ecosistemas Frágiles
      'sp_ecosistemas_fragiles': 'ffffd700',
      'sp_bofedales_inventariados': 'ff808000',
      'sp_bosques_secos': 'ffbdb76b',
      // Restos Arqueológicos
      'sp_sigda_declarados': 'ff800080',
      'sp_sigda_delimitados': 'ffba55d3',
      'sp_sigda_qhapaq_nan': 'ffc71585',
      // Cartografía de Peligros
      'sp_cartografia_peligros_fotointerpretado': 'ffff4500',
      'sp_peligrosgeologicos': 'ffb22222',
      'sp_zonas_criticas': 'ff8b0000',
      'sp_habitat_criticos_serfor': 'ffff4500',
      // Catastro Minero
      'sp_catastro_minero_z19': 'ffd4af37',
      'sp_catastro_minero_z18': 'ffc0c0c0',
      'sp_catastro_minero_z17': 'ffb87333',
      // Ordenamiento Forestal
      'sp_unidad_aprovechamiento': 'ff228b22',
      'sp_concesiones_forestales': 'ff006400',
      'sp_cesiones_uso': 'ff556b2f',
      'sp_bosques_protectores': 'ff8fbc8f',
      'sp_bosques_produccion_permanente': 'ff2e8b57',
      'sp_bosque_local_titulo_habilitante': 'ff66cdaa',
      // Interculturalidad
      'sp_bip_ubigeo': 'ff8b4513',
      'sp_localidad_pertenecientes_pueblos_indigenas': 'ffa0522d',
      'sp_ciras_emitidos': 'ffd2691e',
      'sp_pob_afroperuana': 'ffcd853f',
      // Zonificación
      'sp_zonificacion_acp': 'ff9370db',
      'sp_zonificacion_acr': 'ffba55d3',
      'sp_zonificacion_anp': 'ffda70d6',
    };
    _layerColorMap.addAll(colors);
  }

  Future<File> generateReport({
    required Map<String, Map<String, dynamic>> results,
    required List<SavedDrawingLayer> drawingLayers,
    required List<String> thematicLayers,
    required String queryCode,
  }) async {
    final pdf = pw.Document();
    final font = await _loadFont();
    final logoImage = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _buildPageTheme(font),
        build: (context) => [
          _buildHeader(queryCode, font),
          _buildDrawingLayersSection(drawingLayers, font),
          _buildThematicLayersSection(thematicLayers, font),
          ..._buildResultsSection(results, font),
        ],
      ),
    );

    // Página de visualización
    pdf.addPage(
      pw.MultiPage(
        pageTheme: _buildPageTheme(font),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'VISUALIZACIÓN DE INTERSECCIONES',
              style: pw.TextStyle(
                fontSize: 20,
                font: font,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 20),
          ..._buildVisualizationSection(results, font),
        ],
      ),
    );

    // Página final
    pdf.addPage(
      pw.Page(
        pageTheme: _buildPageTheme(font),
        build: (context) => _buildFooterPage(font, logoImage),
      ),
    );

    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/interseccion_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<pw.Font> _loadFont() async {
    final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    return pw.Font.ttf(fontData);
  }

  Future<pw.ImageProvider> _loadLogo() async {
    final logoData = await rootBundle.load('assets/icon/icon.png');
    return pw.MemoryImage(logoData.buffer.asUint8List());
  }

  pw.PageTheme _buildPageTheme(pw.Font font) {
    return pw.PageTheme(
      theme: pw.ThemeData.withFont(base: font),
      pageFormat: PdfPageFormat.a4,
      buildBackground: (context) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 1, color: PdfColors.grey300),
        ),
      ),
    );
  }

  pw.Widget _buildHeader(String queryCode, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Header(
            level: 0,
            child: pw.Text(
              'REPORTE DE RESULTADOS DE SUPERPOSICIÓN',
              style: pw.TextStyle(
                fontSize: 22,
                font: font,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Fecha: ${_formatDateTime(DateTime.now())}',
            style: pw.TextStyle(font: font),
          ),
          pw.Text('Datum: WGS84 – UTM', style: pw.TextStyle(font: font)),
          pw.Text(
            'Código de Consulta: $queryCode',
            style: pw.TextStyle(font: font),
          ),
          pw.Divider(),
        ],
      ),
    );
  }

  pw.Widget _buildDrawingLayersSection(
    List<SavedDrawingLayer> layers,
    pw.Font font,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'CAPAS DE DIBUJO:',
          style: pw.TextStyle(
            font: font,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        _buildDrawingLayersTable(layers, font),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildDrawingLayersTable(
    List<SavedDrawingLayer> layers,
    pw.Font font,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('Nombre', font),
            _tableHeader('Coordenadas WGS84 - UTM', font),
            _tableHeader('Medida', font),
            _tableHeader('Puntos', font),
            _tableHeader('Líneas', font),
            _tableHeader('Polígonos', font),
          ],
        ),
        ...layers.map((layer) => _buildDrawingLayerRow(layer, font)),
      ],
    );
  }

  pw.TableRow _buildDrawingLayerRow(SavedDrawingLayer layer, pw.Font font) {
    return pw.TableRow(
      children: [
        _tableCell(layer.name, font),
        _coordsCell(layer, font),
        _measureCell(layer, font),
        _tableCell(layer.points.length.toString(), font),
        _tableCell(layer.lines.length.toString(), font),
        _tableCell(layer.polygons.length.toString(), font),
      ],
    );
  }

  pw.Widget _coordsCell(SavedDrawingLayer layer, pw.Font font) {
    if (layer.lines.isNotEmpty) {
      final pts = layer.lines.first.polyline.points;
      if (pts.isNotEmpty) {
        final startUtm = GeometryUtils.latLngToUtmString(pts.first);
        final endUtm = GeometryUtils.latLngToUtmString(pts.last);
        return pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Inicio: $startUtm',
                style: pw.TextStyle(font: font, fontSize: 8),
              ),
              pw.Text(
                'Fin: $endUtm',
                style: pw.TextStyle(font: font, fontSize: 8),
              ),
            ],
          ),
        );
      }
    } else if (layer.polygons.isNotEmpty) {
      final centroid = GeometryUtils.calculateCentroid(
        layer.polygons.first.polygon.points,
      );
      final utm = GeometryUtils.latLngToUtmString(centroid);
      return _tableCell('Centroide: $utm', font, fontSize: 8);
    } else if (layer.points.isNotEmpty) {
      final utm = GeometryUtils.latLngToUtmString(
        layer.points.first.marker.point,
      );
      return _tableCell('Punto: $utm', font, fontSize: 8);
    }
    return _tableCell('-', font);
  }

  pw.Widget _measureCell(SavedDrawingLayer layer, pw.Font font) {
    if (layer.lines.isNotEmpty) {
      final pts = layer.lines.first.polyline.points;
      final meters = GeometryUtils.calculateLineLength(pts);
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${(meters / 1000).toStringAsFixed(2)} km',
              style: pw.TextStyle(font: font),
            ),
            pw.Text(
              '${meters.toStringAsFixed(0)} m',
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
          ],
        ),
      );
    } else if (layer.polygons.isNotEmpty) {
      final area = GeometryUtils.calculatePolygonArea(
        layer.polygons.first.polygon.points,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${(area / 10000).toStringAsFixed(2)} Ha',
              style: pw.TextStyle(font: font),
            ),
            pw.Text(
              '${GeometryUtils.formatThousands(area.round())} m²',
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
          ],
        ),
      );
    }
    return _tableCell('-', font);
  }

  pw.Widget _buildThematicLayersSection(List<String> layerIds, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'CAPAS TEMÁTICAS EN CONSULTA:',
          style: pw.TextStyle(
            font: font,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        _buildThematicLayersTable(layerIds, font),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildThematicLayersTable(List<String> layerIds, pw.Font font) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('Nombre de capa', font),
            _tableHeader('Grupo', font),
          ],
        ),
        ...layerIds.map(
          (id) => pw.TableRow(
            children: [
              _tableCell(_getLayerName(id), font),
              _tableCell(_getLayerGroup(id), font),
            ],
          ),
        ),
      ],
    );
  }

  List<pw.Widget> _buildResultsSection(
    Map<String, Map<String, dynamic>> results,
    pw.Font font,
  ) {
    final widgets = <pw.Widget>[];

    widgets.add(
      pw.Text(
        'RESULTADOS DE SUPERPOSICIÓN:',
        style: pw.TextStyle(
          font: font,
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 10));

    for (final entry in results.entries) {
      final layerName = entry.key;
      final features = (entry.value['features'] as List?) ?? [];

      if (features.isEmpty) continue;

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 15, bottom: 5),
          child: pw.Text(
            'Capa: ${_formatLayerName(layerName)}',
            style: pw.TextStyle(
              font: font,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
        ),
      );

      final byInput = <String, List<dynamic>>{};
      for (final feature in features) {
        final props = (feature['properties'] as Map?) ?? {};
        final input1 = (props['__input1']?.toString() ?? '').trim();
        final key = input1.isNotEmpty ? input1 : 'Dibujo';
        byInput.putIfAbsent(key, () => []).add(feature);
      }

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('Input 1', font),
            _tableHeader('Descripción', font),
            _tableHeader('Área en Superposición', font),
          ],
        ),
      ];

      for (final group in byInput.entries) {
        final drawingName =
            ((group.value.first['properties'] as Map)['__drawing_name'] ?? '')
                .toString();
        rows.add(
          pw.TableRow(
            children: [
              _tableCell(drawingName, font),
              _tableCell(
                _buildIntersectionDescription(layerName, group.value),
                font,
              ),
              _tableCell(_buildOverlapAreaCell(group.value), font),
            ],
          ),
        );
      }

      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: {
            0: const pw.FixedColumnWidth(80),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FixedColumnWidth(80),
          },
          children: rows,
        ),
      );
    }

    return widgets;
  }

  List<pw.Widget> _buildVisualizationSection(
    Map<String, Map<String, dynamic>> results,
    pw.Font font,
  ) {
    final widgets = <pw.Widget>[];

    for (final entry in results.entries) {
      final layerColor = _getColorForLayer(entry.key);
      widgets.add(
        pw.Text(
          'Capa: ${_formatLayerName(entry.key)}',
          style: pw.TextStyle(
            font: font,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_buildIntersectionVisualization(entry.value, layerColor));
      widgets.add(pw.SizedBox(height: 20));
    }

    return widgets;
  }

  pw.Widget _buildIntersectionVisualization(dynamic geoJson, Color layerColor) {
    try {
      final features = geoJson['features'] as List<dynamic>;
      final polygons = <List<LatLng>>[];
      final lines = <List<LatLng>>[];
      final points = <LatLng>[];

      for (final feature in features) {
        final geometry = feature['geometry'];
        final type = geometry['type'] as String;
        final coords = geometry['coordinates'];

        switch (type) {
          case 'Polygon':
            polygons.add(_parsePolygon(coords[0]));
            break;
          case 'MultiPolygon':
            for (final poly in coords) {
              polygons.add(_parsePolygon(poly[0]));
            }
            break;
          case 'LineString':
            lines.add(_parseLine(coords));
            break;
          case 'MultiLineString':
            for (final line in coords) {
              lines.add(_parseLine(line));
            }
            break;
          case 'Point':
            points.add(_parsePoint(coords));
            break;
        }
      }

      if (polygons.isEmpty && lines.isEmpty && points.isEmpty) {
        return pw.Container(
          height: 100,
          alignment: pw.Alignment.center,
          child: pw.Text('No hay geometrías para visualizar'),
        );
      }

      final bounds = _calculateBounds([
        ...polygons.expand((p) => p),
        ...lines.expand((l) => l),
        ...points,
      ]);
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
          painter: (canvas, size) => _paintGeometries(
            canvas: canvas,
            size: size,
            bounds: bounds,
            polygons: polygons,
            lines: lines,
            points: points,
            color: pdfColor,
          ),
        ),
      );
    } catch (e) {
      return pw.Container(
        height: 100,
        alignment: pw.Alignment.center,
        child: pw.Text('Error al visualizar: $e'),
      );
    }
  }

  void _paintGeometries({
    required PdfGraphics canvas,
    required PdfPoint size,
    required Map<String, double> bounds,
    required List<List<LatLng>> polygons,
    required List<List<LatLng>> lines,
    required List<LatLng> points,
    required PdfColor color,
  }) {
    final dataAspect =
        (bounds['maxLng']! - bounds['minLng']!) /
        (bounds['maxLat']! - bounds['minLat']!);
    final canvasAspect = size.x / size.y;

    double drawWidth, drawHeight;
    if (dataAspect > canvasAspect) {
      drawWidth = size.x;
      drawHeight = size.x / dataAspect;
    } else {
      drawHeight = size.y;
      drawWidth = size.y * dataAspect;
    }

    final offsetX = (size.x - drawWidth) / 2;
    final offsetY = (size.y - drawHeight) / 2;

    PdfPoint project(LatLng p) {
      final xNorm =
          (p.longitude - bounds['minLng']!) /
          (bounds['maxLng']! - bounds['minLng']!);
      final yNorm =
          (p.latitude - bounds['minLat']!) /
          (bounds['maxLat']! - bounds['minLat']!);
      return PdfPoint(
        offsetX + xNorm * drawWidth,
        offsetY + yNorm * drawHeight,
      );
    }

    // Dibujar polígonos
    canvas.setFillColor(color);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);

    for (final polygon in polygons) {
      if (polygon.length < 3) continue;
      final pts = polygon.map(project).toList();
      canvas.moveTo(pts[0].x, pts[0].y);
      for (var i = 1; i < pts.length; i++) {
        canvas.lineTo(pts[i].x, pts[i].y);
      }
      canvas.closePath();
      canvas.fillAndStrokePath();
    }

    // Dibujar líneas
    canvas.setStrokeColor(color);
    canvas.setLineWidth(1.2);

    for (final line in lines) {
      if (line.length < 2) continue;
      final pts = line.map(project).toList();
      canvas.moveTo(pts[0].x, pts[0].y);
      for (var i = 1; i < pts.length; i++) {
        canvas.lineTo(pts[i].x, pts[i].y);
      }
      canvas.strokePath();
    }

    // Dibujar puntos
    canvas.setFillColor(color);

    for (final p in points) {
      final pt = project(p);
      canvas.drawEllipse(pt.x - 3, pt.y - 3, 6, 6);
      canvas.fillPath();
    }

    // Flecha Norte
    _drawNorthArrow(canvas, size.x - 25, size.y - 25);
  }

  void _drawNorthArrow(PdfGraphics canvas, double x, double y) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.5);

    canvas.moveTo(x, y - 15);
    canvas.lineTo(x, y + 15);
    canvas.strokePath();

    canvas.moveTo(x - 4, y + 8);
    canvas.lineTo(x, y + 15);
    canvas.lineTo(x + 4, y + 8);
    canvas.strokePath();
  }

  Map<String, double> _calculateBounds(List<LatLng> points) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final latRange = maxLat - minLat == 0 ? 0.001 : maxLat - minLat;
    final lngRange = maxLng - minLng == 0 ? 0.001 : maxLng - minLng;

    return {
      'minLat': minLat - latRange * 0.05,
      'maxLat': maxLat + latRange * 0.05,
      'minLng': minLng - lngRange * 0.05,
      'maxLng': maxLng + lngRange * 0.05,
    };
  }

  List<LatLng> _parsePolygon(List<dynamic> coords) {
    return coords
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();
  }

  List<LatLng> _parseLine(List<dynamic> coords) {
    return coords
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();
  }

  LatLng _parsePoint(List<dynamic> coords) {
    return LatLng(
      (coords[1] is int ? (coords[1] as int).toDouble() : coords[1] as double),
      (coords[0] is int ? (coords[0] as int).toDouble() : coords[0] as double),
    );
  }

  pw.Widget _buildFooterPage(pw.Font font, pw.ImageProvider logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Spacer(),
          pw.Text(
            'Fecha de Reporte: ${_formatDateTime(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
          pw.Text(
            'Usuario: Admin 1',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
          pw.Text(
            'Autor: InGeo V1-2025',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
          pw.SizedBox(height: 20),
          pw.Center(child: pw.Image(logo, width: 200)),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'Transforma tu celular en un GPS inteligente y analiza la viabilidad geográfica de tus proyectos en tiempo real y con datos de campo',
              style: pw.TextStyle(font: font, fontSize: 10),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _buildIntersectionDescription(String layerId, List<dynamic> features) {
    final layerFields = {
      // ANP
      'sp_anp_nacionales_definidas': ['ANP_Nacion'],
      'sp_zonas_amortiguamiento': ['ZA_ANP'],
      'sp_zonas_reservadas': ['zr_nomb'],
      'sp_areas_conservacion_regional': ['acr_nomb'],
      'sp_areas_conservacion_privada': ['acp_nomb'],
      'sp_ecosistemas_fragiles': ['NOMEF'],
      'sp_bofedales_inventariados': ['Desc_cober'],
      'sp_bosques_secos': ['Bosques Secos'],

      // SIGDA / Arqueológicos
      'sp_sigda_declarados': ['nombre_map'],
      'sp_sigda_delimitados': ['nomb_map'],
      'sp_sigda_qhapaq_nan': ['d_camclasv'],

      // Peligros
      'sp_peligrosgeologicos': ['PELIGRO_ES'],
      'sp_puntos_geodesicos': ['PELIGRO_ES'],
      'sp_zonas_criticas': ['PELIGRO_ES'],
      'sp_cartografia_peligros_fotointerpretado': ['PELIGRO_ES'],
      'sp_zonas_criticas_fen_2023_2024': ['Peligro'],

      // Political / Social
      'sp_centros_poblados_inei': ['NOMCCPP_1'],
      'sp_comunidades_campesinas': ['nom_comuni'],
      'sp_comunidades_nativas': ['nom_comuni'],
      'sp_departamentos': ['NOMBDEP'],
      'sp_provincias': ['NOMBPROV'],
      'sp_distritos': ['NOMBDIST'],

      // Hydrography
      'sp_vertientes': ['NOM_VERT'],
      'sp_cuencas': ['NOM_UH'],

      // Existing / Others
      'sp_habitat_criticos_serfor': ['NOMHC'],
      'sp_catastro_minero_z19': ['CONCESION'],
      'sp_catastro_minero_z18': ['CONCESION'],
      'sp_catastro_minero_z17': ['CONCESION'],
      'sp_unidad_aprovechamiento': ['NOMTIT'],
      'sp_concesiones_forestales': ['NOMTIT'],
      'sp_cesiones_uso': ['NOMTIT'],
      'sp_bosques_protectores': ['NOMBOS'],
      'sp_bosques_produccion_permanente': ['ZONA'],
      'sp_bosque_local_titulo_habilitante': ['NOMTIT'],
      'sp_bip_ubigeo': ['nombre'],
      'sp_localidad_pertenecientes_pueblos_indigenas': ['nombre'],
      'sp_ciras_emitidos': ['cira'],
      'sp_pob_afroperuana': ['pob_afrope'],
      'sp_zonificacion_acp': ['tz_nomb'],
      'sp_zonificacion_acr': ['tz_nomb'],
      'sp_zonificacion_anp': ['tz_nomb'],
    };

    if (features.isEmpty) return '';

    // Collect unique descriptions from all features
    final descriptions = <String>{};

    for (final feature in features) {
      final props = (feature['properties'] ?? {}) as Map;
      String? desc;

      final fields = layerFields[layerId];
      if (fields != null) {
        for (final field in fields) {
          final value = _getPropertyValue(props, field);
          if (value.isNotEmpty) {
            desc = value;
            break;
          }
        }
      }

      // Fallback to name/nombre search if no specific field matched
      if (desc == null || desc.isEmpty) {
        final name = props['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          desc = name;
        } else {
          for (final entry in props.entries) {
            final k = entry.key.toString().toLowerCase();
            final v = entry.value?.toString().trim() ?? '';
            if (v.isNotEmpty && (k.contains('name') || k.contains('nombre'))) {
              desc = v;
              break;
            }
          }
        }
      }

      if (desc != null && desc.isNotEmpty) {
        descriptions.add(desc);
      }
    }

    if (descriptions.isNotEmpty) {
      // Limit description length to avoid PDF overflow
      final list = descriptions.toList();
      if (list.length > 15) {
        return '${list.take(15).join(", ")} ... y ${list.length - 15} más.';
      }
      return list.join(', ');
    }

    return _getLayerDisplayName(layerId);
  }

  String _buildOverlapAreaCell(List<dynamic> features) {
    try {
      bool hasPolygon = false;
      bool hasLine = false;
      bool hasPoint = false;

      for (final f in features) {
        final type = f['geometry']['type'] as String;
        if (type.contains('Polygon')) hasPolygon = true;
        if (type.contains('LineString')) hasLine = true;
        if (type.contains('Point')) hasPoint = true;
      }

      if (hasPoint && !hasPolygon && !hasLine) return 'Si / No';

      if (hasLine && !hasPolygon) {
        double totalLen = 0;
        final distance = Distance();

        for (final f in features) {
          final coords = f['geometry']['coordinates'] as List;
          if (f['geometry']['type'] == 'LineString') {
            totalLen += _calculateLineLength(coords, distance);
          } else if (f['geometry']['type'] == 'MultiLineString') {
            for (final line in coords) {
              totalLen += _calculateLineLength(line, distance);
            }
          }
        }

        return '${totalLen.toStringAsFixed(2)} m\n${(totalLen / 1000).toStringAsFixed(4)} Km';
      }

      if (hasPolygon) {
        double totalArea = 0;
        for (final f in features) {
          final coords = f['geometry']['coordinates'];
          final type = f['geometry']['type'];

          if (type == 'Polygon') {
            totalArea += _calculatePolygonArea(coords);
          } else if (type == 'MultiPolygon') {
            for (final poly in coords) {
              totalArea += _calculatePolygonArea(poly);
            }
          }
        }

        final ha = totalArea / 10000.0;
        final formattedArea = GeometryUtils.formatThousands(totalArea.round());
        return '$formattedArea m²\n${ha.toStringAsFixed(4)} Ha';
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  double _calculateLineLength(List<dynamic> coords, Distance distance) {
    double total = 0;
    final points = coords
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();

    for (int i = 0; i < points.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  double _calculatePolygonArea(List<dynamic> polygon) {
    final outer = polygon[0] as List;
    final points = outer
        .map(
          (c) => LatLng(
            (c[1] is int ? (c[1] as int).toDouble() : c[1] as double),
            (c[0] is int ? (c[0] as int).toDouble() : c[0] as double),
          ),
        )
        .toList();

    return GeometryUtils.calculatePolygonArea(points);
  }

  String _getLayerName(String layerId) {
    for (final g in _layerGroups) {
      for (final item in g.items) {
        if (item.layerId == layerId) return item.title;
      }
    }
    return layerId.replaceAll('sp_', '').replaceAll('_', ' ');
  }

  String _getLayerGroup(String layerId) {
    for (final g in _layerGroups) {
      for (final item in g.items) {
        if (item.layerId == layerId) return g.title;
      }
    }
    return '';
  }

  String _getLayerDisplayName(String layerId) {
    final displayNames = {
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
      'sp_habitat_criticos_serfor': 'Hábitat Críticos (SERFOR)',
      'sp_catastro_minero_z19': 'Catastro Minero Z19',
      'sp_catastro_minero_z18': 'Catastro Minero Z18',
      'sp_catastro_minero_z17': 'Catastro Minero Z17',
      'sp_unidad_aprovechamiento': 'Unidades de Aprovechamiento',
      'sp_concesiones_forestales': 'Concesiones Forestales',
      'sp_cesiones_uso': 'Cesiones en Uso',
      'sp_bosques_protectores': 'Bosques Protectores',
      'sp_bosques_produccion_permanente': 'Bosques Producción Permanente',
      'sp_bosque_local_titulo_habilitante': 'Bosques Locales',
      'sp_bip_ubigeo': 'Base de Datos Pueblos Indígenas',
      'sp_localidad_pertenecientes_pueblos_indigenas': 'Localidades PPII',
      'sp_ciras_emitidos': 'CIRAS Emitidos',
      'sp_pob_afroperuana': 'Población Afroperuana',
      'sp_zonificacion_acp': 'Zonificación ACP',
      'sp_zonificacion_acr': 'Zonificación ACR',
      'sp_zonificacion_anp': 'Zonificación ANP',
    };

    return displayNames[layerId] ?? _getLayerName(layerId);
  }

  Color _getColorForLayer(String layerName) {
    for (final entry in _layerColorMap.entries) {
      if (layerName.contains(entry.key)) {
        return Color(int.parse('0x${entry.value}'));
      }
    }

    final random = math.Random(layerName.hashCode);
    return Color(0xff000000 + random.nextInt(0xFFFFFF));
  }

  String _formatLayerName(String layerKey) {
    return layerKey
        .replaceAll('sp_anp_nacionales_definidas', 'ANP Nacionales')
        .replaceAll('sp_zonas_amortiguamiento', 'Zonas de Amortiguamiento')
        .replaceAll('sp_', '')
        .replaceAll('_', ' ')
        .toUpperCase();
  }

  String _getPropertyValue(Map props, String key) {
    final direct = props[key];
    if (direct != null) return direct.toString();

    final target = key.toLowerCase().trim();
    for (final entry in props.entries) {
      if (entry.key.toString().toLowerCase().trim() == target) {
        return (entry.value ?? '').toString();
      }
    }
    return '';
  }

  String _formatDateTime(DateTime dt) {
    return dt.toString().split('.')[0];
  }

  pw.Widget _tableHeader(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _tableCell(String text, pw.Font font, {double fontSize = 10}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: fontSize),
      ),
    );
  }
}
