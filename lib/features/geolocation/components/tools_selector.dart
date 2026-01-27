import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

class ToolsSelector extends StatelessWidget {
  final Function() onMeasureDistance;
  final Function(LatLng) onCopyCoordinates;
  final LatLng currentPosition;

  const ToolsSelector({
    super.key,
    required this.onMeasureDistance,
    required this.onCopyCoordinates,
    required this.currentPosition,
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
        children: [
          _ToolOption(
            title: 'Medir distancia',
            icon: Icons.straighten,
            onTap: onMeasureDistance,
          ),
          const Divider(height: 1),
          _ToolOption(
            title: 'Copiar coordenadas',
            icon: Icons.content_copy,
            onTap: () => onCopyCoordinates(currentPosition),
          ),
          const Divider(height: 1),
          _ToolOption(
            title: 'Compartir ubicación',
            icon: Icons.share_location,
            onTap: () {
              Share.share(
                'Mi ubicación: ${currentPosition.latitude}, ${currentPosition.longitude}',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ToolOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ToolOption({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: Colors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}