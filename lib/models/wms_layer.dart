class WmsLayer {
  final String id;
  final String name; // Título para mostrar
  final String url; // URL del servicio WMS
  final String layerName; // Nombre de la capa en el servicio WMS
  final DateTime timestamp; // Fecha de creación
  final bool isVisible; // Estado de visibilidad

  WmsLayer({
    required this.id,
    required this.name,
    required this.url,
    required this.layerName,
    required this.timestamp,
    this.isVisible = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'layerName': layerName,
      'timestamp': timestamp.toIso8601String(),
      'isVisible': isVisible,
    };
  }

  factory WmsLayer.fromJson(Map<String, dynamic> json) {
    return WmsLayer(
      id: json['id'],
      name: json['name'],
      url: json['url'],
      layerName: json['layerName'],
      timestamp: DateTime.parse(json['timestamp']),
      isVisible: json['isVisible'] ?? true,
    );
  }
}
