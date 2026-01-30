import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/features/geolocation/components/KmlParser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:uri_content/uri_content.dart';

class ImportLayersUtil {
  static Future<SavedDrawingLayer?> importKmlOrKmz() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kml', 'kmz', 'KML', 'KMZ'],
    );

    if (result == null || result.files.single.path == null) return null;

    final path = result.files.single.path!;
    final fileName = result.files.single.name;

    return importKmlOrKmzFromPath(path, fileName: fileName);
  }

  static Future<SavedDrawingLayer?> importKmlOrKmzFromPath(
    String path, {
    String? fileName,
  }) async {
    File file;

    // Manejar URIs de contenido de Android
    if (path.startsWith('content://')) {
      try {
        final tempDir = await getTemporaryDirectory();

        // 1. Crear archivo temporal inicial (sin extensión definitiva aún)
        final tempRawFile = File(
          '${tempDir.path}/temp_raw_${DateTime.now().millisecondsSinceEpoch}',
        );

        // 2. Usar stream para descargar, evitando cargar todo en memoria y reduciendo timeouts
        final uriContent = UriContent();
        final stream = uriContent.getContentStream(Uri.parse(path));
        final sink = tempRawFile.openWrite();

        // Añadir timeout para evitar que se quede "Importando..." indefinidamente
        await sink
            .addStream(stream)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException(
                  'Tiempo de espera agotado al descargar el archivo',
                );
              },
            );

        await sink.flush();
        await sink.close();

        // 3. Leer primeros bytes ("números mágicos") para detectar tipo
        List<int> firstBytes = [];
        try {
          firstBytes = await tempRawFile.openRead(0, 4).first;
        } catch (_) {
          // Ignorar si el archivo está vacío
        }

        String extension = '.kml'; // Por defecto
        if (firstBytes.length >= 4) {
          // Firma ZIP (PK..) para KMZ: 50 4B 03 04
          if (firstBytes[0] == 0x50 &&
              firstBytes[1] == 0x4B &&
              firstBytes[2] == 0x03 &&
              firstBytes[3] == 0x04) {
            extension = '.kmz';
          }
        }

        // 4. Renombrar archivo con la extensión correcta
        final tempFileName =
            fileName ??
            'imported_${DateTime.now().millisecondsSinceEpoch}$extension';

        // Asegurar que el nombre tenga la extensión
        final finalName = tempFileName.toLowerCase().endsWith(extension)
            ? tempFileName
            : '$tempFileName$extension';

        final finalFile = await tempRawFile.rename(
          '${tempDir.path}/$finalName',
        );

        file = finalFile;
        path = finalFile.path;
      } catch (e) {
        debugPrint('Error al resolver content URI con uri_content: $e');
        return null;
      }
    } else {
      file = File(path);
    }
    final lowerPath = path.toLowerCase();
    final effectiveFileName =
        fileName ?? path.split(Platform.pathSeparator).last;

    List<LabeledMarker> allMarkers = [];
    List<LabeledPolyline> allPolylines = [];
    List<LabeledPolygon> allPolygons = [];
    List<GeometryData> allGeometries = [];
    Map<String, dynamic> fileAttributes = {};

    if (lowerPath.endsWith('.kmz')) {
      final bytes = File(path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.name.toLowerCase().endsWith('.kml')) {
          final kmlContent = String.fromCharCodes(file.content as List<int>);
          final parser = KmlParser(XmlDocument.parse(kmlContent));

          allMarkers.addAll(parser.parsePlacemarks());
          allPolylines.addAll(parser.parsePolylines());
          allPolygons.addAll(parser.parsePolygons());
          allGeometries.addAll(parser.parseAllGeometries());

          fileAttributes = _extractFileAttributes(
            XmlDocument.parse(kmlContent),
            effectiveFileName,
            path,
          );
        }
      }
    } else if (lowerPath.endsWith('.kml')) {
      final kmlContent = await File(path).readAsString();
      final parser = KmlParser(XmlDocument.parse(kmlContent));

      allMarkers = parser.parsePlacemarks();
      allPolylines = parser.parsePolylines();
      allPolygons = parser.parsePolygons();
      allGeometries = parser.parseAllGeometries();

      fileAttributes = _extractFileAttributes(
        XmlDocument.parse(kmlContent),
        effectiveFileName,
        path,
      );
    } else {
      return null;
    }

    if (allMarkers.isEmpty &&
        allPolylines.isEmpty &&
        allPolygons.isEmpty &&
        allGeometries.isEmpty) {
      debugPrint('No se encontraron elementos en el archivo.');
      return null;
    }

    return SavedDrawingLayer(
      id: 'external_layer_${DateTime.now().millisecondsSinceEpoch}',
      name: effectiveFileName,
      points: allMarkers,
      lines: allPolylines,
      polygons: allPolygons,
      rawGeometries: allGeometries,
      timestamp: DateTime.now(),
      attributes: fileAttributes,
    );
  }

  // Método para extraer atributos del archivo KML
  static Map<String, dynamic> _extractFileAttributes(
    XmlDocument document,
    String fileName,
    String filePath,
  ) {
    final attributes = <String, dynamic>{};

    // Información básica del archivo
    attributes['fileName'] = fileName;
    attributes['filePath'] = filePath;
    attributes['fileSize'] = File(filePath).lengthSync();
    attributes['importDate'] = DateTime.now().toIso8601String();

    // Extraer información del documento KML
    final kmlElement = document.findAllElements('kml').first;
    final documentElement = kmlElement.findElements('Document').firstOrNull;

    if (documentElement != null) {
      // Nombre del documento
      final nameElement = documentElement.findElements('name').firstOrNull;
      if (nameElement != null) {
        attributes['documentName'] = nameElement.text;
      }

      // Descripción del documento
      final descriptionElement = documentElement
          .findElements('description')
          .firstOrNull;
      if (descriptionElement != null) {
        attributes['description'] = descriptionElement.text;
      }

      // Autor/Creador
      final authorElement = documentElement
          .findElements('atom:author')
          .firstOrNull;
      if (authorElement != null) {
        attributes['author'] = authorElement.text;
      }
    }

    // Contar elementos
    final placemarks = document.findAllElements('Placemark');
    attributes['totalPlacemarks'] = placemarks.length;

    int pointCount = 0;
    int lineCount = 0;
    int polygonCount = 0;

    for (final placemark in placemarks) {
      if (placemark.findElements('Point').isNotEmpty) {
        pointCount++;
      } else if (placemark.findElements('LineString').isNotEmpty) {
        lineCount++;
      } else if (placemark.findElements('Polygon').isNotEmpty) {
        polygonCount++;
      }
    }

    attributes['pointCount'] = pointCount;
    attributes['lineCount'] = lineCount;
    attributes['polygonCount'] = polygonCount;

    return attributes;
  }

  // Método para mostrar los atributos del archivo
  static void showFileAttributes(
    BuildContext context,
    Map<String, dynamic> attributes,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Atributos del Archivo'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAttributeRow(
                  'Nombre del archivo:',
                  attributes['fileName'] ?? 'N/A',
                ),
                _buildAttributeRow(
                  'Tamaño:',
                  '${(attributes['fileSize'] ?? 0 / 1024).toStringAsFixed(2)} KB',
                ),
                _buildAttributeRow(
                  'Fecha de importación:',
                  _formatDate(attributes['importDate']),
                ),
                if (attributes['documentName'] != null)
                  _buildAttributeRow(
                    'Nombre del documento:',
                    attributes['documentName'],
                  ),
                if (attributes['description'] != null)
                  _buildAttributeRow('Descripción:', attributes['description']),
                if (attributes['author'] != null)
                  _buildAttributeRow('Autor:', attributes['author']),
                const Divider(),
                const Text(
                  'Contenido:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildAttributeRow(
                  'Total de elementos:',
                  '${attributes['totalPlacemarks'] ?? 0}',
                ),
                _buildAttributeRow(
                  'Puntos:',
                  '${attributes['pointCount'] ?? 0}',
                ),
                _buildAttributeRow(
                  'Líneas:',
                  '${attributes['lineCount'] ?? 0}',
                ),
                _buildAttributeRow(
                  'Polígonos:',
                  '${attributes['polygonCount'] ?? 0}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildAttributeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  static String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}
