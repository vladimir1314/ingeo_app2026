import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WmsLayerInfo {
  final String name;
  final String title;

  WmsLayerInfo({required this.name, required this.title});
}

Future<List<WmsLayerInfo>> fetchWmsLayers(String getCapabilitiesUrl) async {
  final response = await http.get(Uri.parse(getCapabilitiesUrl));

  if (response.statusCode != 200) {
    throw Exception('Error al obtener GetCapabilities');
  }

  final document = XmlDocument.parse(response.body);
  final layers = <WmsLayerInfo>[];

  // Busca todas las capas hijas dentro de Layer
  final layerElements = document.findAllElements('Layer');

  for (final layer in layerElements) {
    final nameElement = layer.getElement('Name');
    final titleElement = layer.getElement('Title');

    if (nameElement != null && titleElement != null) {
      layers.add(WmsLayerInfo(
        name: nameElement.text,
        title: titleElement.text,
      ));
    }
  }

  return layers;
}
