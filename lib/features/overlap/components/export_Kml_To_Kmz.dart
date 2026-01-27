import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<File> _exportKmlToKmz(
    String kmlContent, String fileName, String imageUrl) async {
  final tempDir = await getTemporaryDirectory();

  // Crear archivo KML
  final kmlFile = File('${tempDir.path}/doc.kml');
  await kmlFile.writeAsString(kmlContent);

  // Descargar la imagen WMS para incluirla en el KMZ (opcional, pero recomendado)
  // Si no la descargas, Google Earth intentará cargarla desde la URL al abrir
  // Pero si quieres que funcione offline, debes empaquetarla

  final kmzFile = File('${tempDir.path}/$fileName.kmz');

  final encoder = ZipFileEncoder();
  encoder.create(kmzFile.path);
  encoder.addFile(kmlFile);

  // Opcional: descargar y empaquetar la imagen
  try {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode == 200) {
      final imageFile = File('${tempDir.path}/overlay.png');
      await imageFile.writeAsBytes(response.bodyBytes);
      encoder.addFile(imageFile);

      // Reemplazar la URL en el KML por la ruta interna
      final updatedKmlContent = kmlContent.replaceAll(imageUrl, 'overlay.png');
      final updatedKmlFile = File('${tempDir.path}/doc.kml');
      await updatedKmlFile.writeAsString(updatedKmlContent);
      encoder.addFile(updatedKmlFile);
    }
  } catch (e) {
    print("No se pudo descargar la imagen WMS: $e");
    // Continúa sin la imagen empaquetada (Google Earth la cargará online)
  }

  encoder.close();
  return kmzFile;
}
