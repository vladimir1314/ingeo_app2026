import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'wms_layer_info.dart';

Future<List<WmsLayerInfo>> fetchWmsLayersFromUrl(String baseUrl) async {
  final fullUrl =
      '$baseUrl${baseUrl.contains("?") ? "&" : "?"}service=WMS&request=GetCapabilities';
  final response = await http.get(Uri.parse(fullUrl));

  if (response.statusCode != 200) {
    throw Exception('No se pudo obtener las capas WMS');
  }

  final document = XmlDocument.parse(response.body);
  final layers = <WmsLayerInfo>[];

  for (final layer in document.findAllElements('Layer')) {
    final name = layer.getElement('Name')?.text;
    final title = layer.getElement('Title')?.text;
    print('name: $name, title: $title');
    if (name != null && title != null) {
      layers.add(WmsLayerInfo(name: name, title: title));
    }
  }

  return layers;
}
