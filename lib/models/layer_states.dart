class LayerGroup {
  final String title;
  final List<LayerItem> items;

  LayerGroup(this.title, this.items);
}

class LayerItem {
  final String title;
  final String layerId;

  LayerItem(this.title, this.layerId);
}
