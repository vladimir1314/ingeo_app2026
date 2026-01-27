import 'package:flutter/material.dart';

class BaseMapSelector extends StatelessWidget {
  final String currentMapType;
  final Function(String) onMapTypeChanged;

  const BaseMapSelector({
    super.key,
    required this.currentMapType,
    required this.onMapTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapTypeOption(
            title: 'OpenStreetMap',
            type: 'osm',
            currentType: currentMapType,
            onSelected: onMapTypeChanged,
            imagePath: 'assets/images/osm_preview.png',
          ),
          const Divider(height: 1),
          _MapTypeOption(
            title: 'Google Maps',
            type: 'google_maps',
            currentType: currentMapType,
            onSelected: onMapTypeChanged,
            imagePath: 'assets/images/google_maps.png',
          ),
          const Divider(height: 1),
          _MapTypeOption(
            title: 'Satélite',
            type: 'satellite',
            currentType: currentMapType,
            onSelected: onMapTypeChanged,
            imagePath: 'assets/images/Unlabeled_satellite.png',
          ),
          const Divider(height: 1),
          _MapTypeOption(
            title: 'Híbrido con etiquetas',
            type: 'hybrid',
            currentType: currentMapType,
            onSelected: onMapTypeChanged,
            imagePath: 'assets/images/Labeled_satellite.png',
          ),
          const Divider(height: 1),
          _MapTypeOption(
            title: 'Terreno',
            type: 'terrain',
            currentType: currentMapType,
            onSelected: onMapTypeChanged,
            imagePath: 'assets/images/terrain_preview.png',
          ),
        ],
      ),
    );
  }
}

class _MapTypeOption extends StatelessWidget {
  final String title;
  final String type;
  final String currentType;
  final Function(String) onSelected;
  final String imagePath;

  const _MapTypeOption({
    required this.title,
    required this.type,
    required this.currentType,
    required this.onSelected,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = type == currentType;

    return InkWell(
      onTap: () => onSelected(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isSelected ? Colors.grey[200] : Colors.transparent,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                imagePath,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
