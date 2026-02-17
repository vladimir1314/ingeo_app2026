import 'dart:io';
import 'dart:convert';

import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

Future<File> exportLayersByFolderToKMLorKMZ(
  Map<String, List<SavedDrawingLayer>> layersByFolder,
  String format, [
  String? fileName,
]) async {
  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
  buffer.writeln('<Document>');

  // Create archive for KMZ
  final archive = Archive();
  int photoCounter = 0;

  // Iterate through folders
  for (final folderEntry in layersByFolder.entries) {
    final folderName = folderEntry.key;
    final layers = folderEntry.value;

    if (layers.isEmpty) continue;

    buffer.writeln('<Folder><name>$folderName</name>');

    for (final layer in layers) {
      final layerName = _xmlEscape(layer.name);
      buffer.writeln('<Folder><name>$layerName</name>');

      for (final point in layer.points) {
        final photoRefs = <String>[];

        // Add photos to archive and create references
        if (point.photos.isNotEmpty) {
          for (final photo in point.photos) {
            final photoName = 'files/photo_${photoCounter++}.jpg';
            final photoBytes = await photo.readAsBytes();
            archive.addFile(
              ArchiveFile(photoName, photoBytes.length, photoBytes),
            );
            photoRefs.add(photoName);
          }
        }

        buffer.writeln('''\n<Placemark>
  <name>${point.label}</name>
  <ExtendedData>
    <Data name="locality"><value>${point.locality}</value></Data>
    <Data name="manualCoordinates"><value>${point.manualCoordinates}</value></Data>
    <Data name="observation"><value>${point.observation}</value></Data>''');

        // Add dynamic attributes
        if (point.attributes.isNotEmpty) {
          point.attributes.forEach((key, value) {
            final cleanValue = value
                .toString()
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;');
            buffer.writeln(
              '    <Data name="$key"><value>$cleanValue</value></Data>',
            );
          });
        }

        buffer.writeln(
          '''  </ExtendedData>
  <Point><coordinates>${point.marker.point.longitude},${point.marker.point.latitude},0</coordinates></Point>''',
        );

        // Add photo references if any
        if (photoRefs.isNotEmpty) {
          buffer.writeln('  <description><![CDATA[');
          for (final photoRef in photoRefs) {
            buffer.writeln('<img src="$photoRef" width="300"/><br/>');
          }
          buffer.writeln(']]></description>');
        }

        buffer.writeln('</Placemark>');
      }

      // Pre-process polygon photos
      // Note: We process photos inside the loop now

      for (final line in layer.lines) {
        final linePhotoRefs = <String>[];
        if (line.photos.isNotEmpty) {
          for (final path in line.photos) {
            final file = File(path);
            if (await file.exists()) {
              final photoName = 'files/photo_${photoCounter++}.jpg';
              final photoBytes = await file.readAsBytes();
              archive.addFile(
                ArchiveFile(photoName, photoBytes.length, photoBytes),
              );
              linePhotoRefs.add(photoName);
            }
          }
        }

        final coords = line.polyline.points
            .map((p) => '${p.longitude},${p.latitude},0')
            .join(' ');
        buffer.writeln('''\n<Placemark>
  <name>${line.label}</name>
  <ExtendedData>
    <Data name="locality"><value>${line.locality}</value></Data>
    <Data name="manualCoordinates"><value>${line.manualCoordinates}</value></Data>
    <Data name="observation"><value>${line.observation}</value></Data>''');

        // Add dynamic attributes
        if (line.attributes.isNotEmpty) {
          line.attributes.forEach((key, value) {
            final cleanValue = value
                .toString()
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;');
            buffer.writeln(
              '    <Data name="$key"><value>$cleanValue</value></Data>',
            );
          });
        }

        buffer.writeln('''  </ExtendedData>
  <LineString>
    <coordinates>$coords</coordinates>
  </LineString>''');

        // Add photo references if any
        if (linePhotoRefs.isNotEmpty) {
          buffer.writeln('  <description><![CDATA[');
          for (final photoRef in linePhotoRefs) {
            buffer.writeln('<img src="$photoRef" width="300"/><br/>');
          }
          buffer.writeln(']]></description>');
        }

        buffer.writeln('</Placemark>\n');
      }

      for (final polygon in layer.polygons) {
        final polygonPhotoRefs = <String>[];
        if (polygon.photos.isNotEmpty) {
          for (final path in polygon.photos) {
            final file = File(path);
            if (await file.exists()) {
              final photoName = 'files/photo_${photoCounter++}.jpg';
              final photoBytes = await file.readAsBytes();
              archive.addFile(
                ArchiveFile(photoName, photoBytes.length, photoBytes),
              );
              polygonPhotoRefs.add(photoName);
            }
          }
        }

        final coords = [
          ...polygon.polygon.points,
          polygon.polygon.points.first,
        ].map((p) => '${p.longitude},${p.latitude},0').join(' ');
        buffer.writeln('''\n<Placemark>
  <name>${polygon.label}</name>
  <ExtendedData>
    <Data name="locality"><value>${polygon.locality}</value></Data>
    <Data name="manualCoordinates"><value>${polygon.manualCoordinates}</value></Data>
    <Data name="observation"><value>${polygon.observation}</value></Data>''');

        // Add dynamic attributes
        if (polygon.attributes.isNotEmpty) {
          polygon.attributes.forEach((key, value) {
            final cleanValue = value
                .toString()
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;');
            buffer.writeln(
              '    <Data name="$key"><value>$cleanValue</value></Data>',
            );
          });
        }

        buffer.writeln('''  </ExtendedData>
  <Polygon>
    <outerBoundaryIs>
      <LinearRing>
        <coordinates>$coords</coordinates>
      </LinearRing>
    </outerBoundaryIs>
  </Polygon>''');

        // Add photo references if any
        if (polygonPhotoRefs.isNotEmpty) {
          buffer.writeln('  <description><![CDATA[');
          for (final photoRef in polygonPhotoRefs) {
            buffer.writeln('<img src="$photoRef" width="300"/><br/>');
          }
          buffer.writeln(']]></description>');
        }

        buffer.writeln('</Placemark>\n');
      }

      buffer.writeln('</Folder>');
    }

    buffer.writeln('</Folder>');
  }

  buffer.writeln('</Document>');
  buffer.writeln('</kml>');

  final directory = await getTemporaryDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final kmlContent = buffer.toString();
  final baseFileName = fileName?.isNotEmpty == true
      ? fileName
      : 'export_by_folders_$timestamp';

  late File file;

  if (format == 'kml') {
    file = File('${directory.path}/$baseFileName.kml');
    await file.writeAsString(kmlContent);
  } else {
    // Add the KML file to the archive (usar longitud real en bytes)
    final kmlBytes = utf8.encode(kmlContent);
    archive.addFile(
      ArchiveFile('doc.kml', kmlBytes.length, kmlBytes),
    );
    final kmzData = ZipEncoder().encode(archive);
    file = File('${directory.path}/$baseFileName.kmz');
    await file.writeAsBytes(kmzData!);
  }

  return file;
}
