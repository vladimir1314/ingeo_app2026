import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';

import 'package:flutter/services.dart';
import 'package:utm/utm.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

class PdfReportGenerator {
  static Future<File> generateReport(List<SavedDrawingLayer> layers) async {
    final pdf = pw.Document();

    final font = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final ttf = pw.Font.ttf(font);

    // Cargar el logo de InGeo
    final logoImage = await rootBundle.load('assets/icon/icon.png');
    final logoImageData = logoImage.buffer.asUint8List();
    final logo = pw.MemoryImage(logoImageData);

    // Añadir contenido al final del documento
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
                  child: pw.Text('Reporte de Geometrías',
                      style: pw.TextStyle(fontSize: 24, font: ttf)),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Fecha: ${DateTime.now().toString().split('.')[0]}',
                    style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 20),
                pw.Text('Resumen General:',
                    style: pw.TextStyle(font: ttf, fontSize: 16)),
                pw.SizedBox(height: 10),
                _buildSummaryTable(layers),
              ],
            ),
          ),
          for (var layer in layers)
            if (layer.id.startsWith('saved_layer_')) ...[
              pw.Header(
                  level: 1,
                  child: pw.Text(layer.name, style: pw.TextStyle(font: ttf))),
              _buildLayerStatistics(layer),
              pw.SizedBox(height: 20),


              pw.SizedBox(height: 20),
              // Insertamos la nueva tabla de detalles ANTES de coordenadas
              _buildObjectDetailsTable(layer),
              pw.SizedBox(height: 20),
              _buildCoordinatesTable(layer),
            ],
          // Añadir la página final con el logo y la información
          pw.SizedBox(height: 40),
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    'Fecha de Reporte: ${DateTime.now().toString().split(".")[0]}',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Usuario: Admin 1',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Autor: InGeo V1-2025',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 40),
                pw.Center(
                  child: pw.Container(
                    width: 300,
                    height: 300,
                    child: pw.Image(logo),
                  ),
                ),
                pw.SizedBox(height: 40),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                          'Transforma tu celular en un GPS inteligente y analiza la viabilidad geográfica',
                          style: const pw.TextStyle(fontSize: 12)),
                      pw.Text(
                          'de tus proyectos en tiempo real y con datos de campo',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
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
    final file = File('${directory.path}/reporte_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());

    try {
      await Share.shareXFiles([XFile(file.path)],
          text: 'Reporte de geometrías (PDF)');
    } catch (_) {}

    return file;
  }



  // Construye la tabla "Detalles de los objetos"
  static pw.Widget _buildObjectDetailsTable(SavedDrawingLayer layer) {
    final children = <pw.Widget>[];

    pw.TableRow _buildHeaderRow() {
      return pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
              padding: const pw.EdgeInsets.all(5), child: pw.Text('Nombre')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5), child: pw.Text('Localidad')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text('Observación')),
        ],
      );
    }

    if (layer.points.isNotEmpty) {
      final rows = <pw.TableRow>[_buildHeaderRow()];
      for (final p in layer.points) {
        final parsed = _parseLabel(p.label);
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['nombre'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['localidad'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['observacion'] ?? '')),
            ],
          ),
        );
      }
      children.add(pw.Header(level: 2, text: 'Puntos'));
      children.add(pw.SizedBox(height: 10));
      children.add(pw.Table(border: pw.TableBorder.all(), children: rows));
      children.add(pw.SizedBox(height: 20));
    }

    if (layer.lines.isNotEmpty) {
      final rows = <pw.TableRow>[_buildHeaderRow()];
      for (final l in layer.lines) {
        final parsed = _parseLabel(l.label);
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['nombre'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['localidad'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['observacion'] ?? '')),
            ],
          ),
        );
      }
      children.add(pw.Header(level: 2, text: 'Líneas - polilineas'));
      children.add(pw.SizedBox(height: 10));
      children.add(pw.Table(border: pw.TableBorder.all(), children: rows));
      children.add(pw.SizedBox(height: 20));
    }

    if (layer.polygons.isNotEmpty) {
      final rows = <pw.TableRow>[_buildHeaderRow()];
      for (final poly in layer.polygons) {
        final parsed = _parseLabel(poly.label);
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['nombre'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['localidad'] ?? '')),
              pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(parsed['observacion'] ?? '')),
            ],
          ),
        );
      }
      children.add(pw.Header(level: 2, text: 'Polígonos'));
      children.add(pw.SizedBox(height: 10));
      children.add(pw.Table(border: pw.TableBorder.all(), children: rows));
      children.add(pw.SizedBox(height: 20));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  // Extrae nombre, localidad y observación desde el label.
  static Map<String, String> _parseLabel(String? label) {
    final result = {
      'nombre': '',
      'localidad': '',
      'observacion': '',
    };
    if (label == null || label.trim().isEmpty) return result;

    final lines = label.split('\n').map((l) => l.trim()).toList();

    // Nombre: primera línea que no sea una clave conocida
    isMeta(String l) {
      final lower = l.toLowerCase();
      return lower.startsWith('coordenadas') ||
          lower.startsWith('localidad') ||
          lower.startsWith('lat') ||
          lower.startsWith('lng') ||
          lower.startsWith('utm') ||
          lower.startsWith('observacion') ||
          lower.startsWith('observación');
    }

    result['nombre'] =
        lines.firstWhere((l) => l.isNotEmpty && !isMeta(l), orElse: () => '');

    for (final l in lines) {
      final lower = l.toLowerCase();
      if (lower.startsWith('localidad')) {
        result['localidad'] =
            l.split(':').length > 1 ? l.split(':')[1].trim() : '';
      } else if (lower.startsWith('observación') ||
          lower.startsWith('observacion')) {
        result['observacion'] =
            l.split(':').length > 1 ? l.split(':')[1].trim() : '';
      }
    }
    return result;
  }



  static pw.Widget _buildSummaryTable(List<SavedDrawingLayer> layers) {
    int totalPoints = 0;
    int totalLines = 0;
    int totalPolygons = 0;

    for (var layer in layers) {
      if (layer.id.startsWith('saved_layer_')) {
        totalPoints += layer.points.length;
        totalLines += layer.lines.length;
        totalPolygons += layer.polygons.length;
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text('Total de Capas')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(layers
                    .where((l) => l.id.startsWith('saved_layer_'))
                    .length
                    .toString())),
          ],
        ),
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text('Total de Puntos')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(totalPoints.toString())),
          ],
        ),
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text('Total de Líneas')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(totalLines.toString())),
          ],
        ),
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text('Total de Polígonos')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(totalPolygons.toString())),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildLayerStatistics(SavedDrawingLayer layer) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Estadísticas de la Capa:'),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatCircle('Puntos', layer.points.length),
            _buildStatCircle('Líneas', layer.lines.length),
            _buildStatCircle('Polígonos', layer.polygons.length),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildStatCircle(String label, int value) {
    return pw.Container(
      height: 60,
      width: 60,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(value.toString()),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }



  static LatLng _getPolygonCentroid(List<LatLng> points) {
    double latitude = 0;
    double longitude = 0;
    for (final point in points) {
      latitude += point.latitude;
      longitude += point.longitude;
    }
    return LatLng(latitude / points.length, longitude / points.length);
  }

  static pw.Widget _buildCoordinatesTable(SavedDrawingLayer layer) {
    final List<pw.TableRow> rows = [];

    // Encabezado
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
              padding: const pw.EdgeInsets.all(5), child: pw.Text('Tipo')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5), child: pw.Text('Nombre')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text('Coordenadas')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5), child: pw.Text('UTM')),
          pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text('Dimensiones')),
        ],
      ),
    );

    // Puntos
    for (var point in layer.points) {
      final latLng = point.marker.point;
      final utm = UTM.fromLatLon(lat: latLng.latitude, lon: latLng.longitude);
      final parsed = _parseLabel(point.label);
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5), child: pw.Text('Punto')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(parsed['nombre'] ?? '')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    '(${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)})')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    '${utm.easting.round()}E ${utm.northing.round()}N ${utm.zoneNumber}${utm.zoneLetter}')),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('')),
          ],
        ),
      );
    }

    // Líneas
    for (var line in layer.lines) {
      final points = line.polyline.points;
      if (points.length < 2) continue;

      final start = points.first;
      final end = points.last;
      final startUtm =
          UTM.fromLatLon(lat: start.latitude, lon: start.longitude);
      final endUtm = UTM.fromLatLon(lat: end.latitude, lon: end.longitude);

      final lenM = _calculateLineLengthMeters(points);
      final lenKm = lenM / 1000.0;
      final parsed = _parseLabel(line.label);

      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5), child: pw.Text('Línea')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(parsed['nombre'] ?? '')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    'Inicio: (${start.latitude.toStringAsFixed(5)}, ${start.longitude.toStringAsFixed(5)})\n'
                    'Fin: (${end.latitude.toStringAsFixed(5)}, ${end.longitude.toStringAsFixed(5)})')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    'Inicio: ${startUtm.easting.round()}E ${startUtm.northing.round()}N ${startUtm.zoneNumber}${startUtm.zoneLetter}\n'
                    'Fin: ${endUtm.easting.round()}E ${endUtm.northing.round()}N ${endUtm.zoneNumber}${endUtm.zoneLetter}')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    '${lenM.toStringAsFixed(2)} m\n${lenKm.toStringAsFixed(3)} km')),
          ],
        ),
      );
    }

    // Polígonos
    for (var polygon in layer.polygons) {
      final parsed = _parseLabel(polygon.label);
      final center = _getPolygonCentroid(polygon.polygon.points);
      final centerUtm =
          UTM.fromLatLon(lat: center.latitude, lon: center.longitude);

      final areaM2 = _calculatePolygonAreaMeters2(polygon.polygon.points);
      final areaKm2 = areaM2 / 1000000.0;

      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text('Polígono')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(parsed['nombre'] ?? '')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    'Centroide: (${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)})')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    '${centerUtm.easting.round()}E ${centerUtm.northing.round()}N ${centerUtm.zoneNumber}${centerUtm.zoneLetter}')),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                    '${areaM2.toStringAsFixed(2)} m²\n${areaKm2.toStringAsFixed(4)} km²')),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Tabla de Coordenadas y Metadatos:',
            style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(),
          children: rows,
        ),
      ],
    );
  }

  static double _calculateLineLengthMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  static double _calculatePolygonAreaMeters2(List<LatLng> points) {
    if (points.length < 3) return 0;
    final utmPoints = points.map((p) {
      final utm = UTM.fromLatLon(lat: p.latitude, lon: p.longitude);
      return [utm.easting, utm.northing];
    }).toList();

    if (utmPoints.first[0] != utmPoints.last[0] ||
        utmPoints.first[1] != utmPoints.last[1]) {
      utmPoints.add(utmPoints.first);
    }

    double area = 0;
    for (int i = 0; i < utmPoints.length - 1; i++) {
      area += utmPoints[i][0] * utmPoints[i + 1][1] -
          utmPoints[i + 1][0] * utmPoints[i][1];
    }
    return area.abs() / 2.0;
  }

  static double _calculatePolygonPerimeter(List<LatLng> points) {
    if (points.length < 2) return 0;
    const distance = Distance();
    double perimeter = 0;
    for (int i = 0; i < points.length - 1; i++) {
      perimeter += distance(points[i], points[i + 1]);
    }
    // Close the polygon
    perimeter += distance(points.last, points.first);
    return perimeter;
  }

  static Future<File> generateExcelReport(
      List<SavedDrawingLayer> layers) async {
    final excel = Excel.createExcel();

    // Crear hojas específicas
    final sheetPoints = excel['Puntos'];
    final sheetLines = excel['Líneas'];
    final sheetPolygons = excel['Polígonos'];

    // Eliminar la hoja por defecto si se desea, o dejarla.
    // Excel crea una hoja "Sheet1" por defecto.
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Encabezados para Puntos
    sheetPoints.appendRow([
      'Capa',
      'Etiqueta',
      'Latitud',
      'Longitud',
      'UTM Este',
      'UTM Norte',
      'Zona',
      'Fecha'
    ]);

    // Encabezados para Líneas
    sheetLines.appendRow([
      'Capa',
      'Etiqueta',
      'Longitud (m)',
      'Inicio Lat',
      'Inicio Lon',
      'Fin Lat',
      'Fin Lon',
      'Fecha'
    ]);

    // Encabezados para Polígonos
    sheetPolygons.appendRow([
      'Capa',
      'Etiqueta',
      'Área (m²)',
      'Perímetro (m)',
      'Centroide Lat',
      'Centroide Lon',
      'Fecha'
    ]);

    for (final layer in layers) {
      // Puntos
      for (final point in layer.points) {
        final latLng = point.marker.point;
        final utm =
            UTM.fromLatLon(lat: latLng.latitude, lon: latLng.longitude);

        sheetPoints.appendRow([
          layer.name,
          point.label,
          latLng.latitude.toStringAsFixed(6),
          latLng.longitude.toStringAsFixed(6),
          utm.easting.round(),
          utm.northing.round(),
          '${utm.zoneNumber}${utm.zoneLetter}',
          layer.timestamp.toString().split('.')[0],
        ]);
      }

      // Líneas
      for (final line in layer.lines) {
        final pts = line.polyline.points;
        if (pts.length < 2) continue;
        
        // Calcular longitud total
        double length = 0;
        final distance = const Distance();
        for (int i = 0; i < pts.length - 1; i++) {
          length += distance(pts[i], pts[i + 1]);
        }

        final start = pts.first;
        final end = pts.last;

        sheetLines.appendRow([
          layer.name,
          line.label,
          length.toStringAsFixed(2),
          start.latitude.toStringAsFixed(6),
          start.longitude.toStringAsFixed(6),
          end.latitude.toStringAsFixed(6),
          end.longitude.toStringAsFixed(6),
          layer.timestamp.toString().split('.')[0],
        ]);
      }

      // Polígonos
      for (final polygon in layer.polygons) {
        if (polygon.polygon.points.length < 3) continue;
        
        final center = _getPolygonCentroid(polygon.polygon.points);
        final area = _calculatePolygonAreaMeters2(polygon.polygon.points);
        final perimeter = _calculatePolygonPerimeter(polygon.polygon.points);

        sheetPolygons.appendRow([
          layer.name,
          polygon.label?.split('\n').first ?? 'Sin etiqueta',
          area.toStringAsFixed(2),
          perimeter.toStringAsFixed(2),
          center.latitude.toStringAsFixed(6),
          center.longitude.toStringAsFixed(6),
          layer.timestamp.toString().split('.')[0],
        ]);
      }
    }

    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final fileName =
        'reporte_geometrias_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }
}
