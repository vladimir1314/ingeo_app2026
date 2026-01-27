import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final Function() onMapTypePressed;
  final Function() onToolsPressed;
  final Function() onFilePressed;
  final Function() onLocationPressed;
  final bool isLoadingLocation;

  const MapControls({
    super.key,
    required this.onMapTypePressed,
    required this.onToolsPressed,
    required this.onFilePressed,
    required this.onLocationPressed,
    required this.isLoadingLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 110,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: 'layers_button',
            mini: true,
            backgroundColor: Colors.white,
            child: const Icon(Icons.layers, color: Colors.blue),
            onPressed: onMapTypePressed,
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'tools_button',
            mini: true,
            backgroundColor: Colors.white,
            child: const Icon(Icons.build, color: Colors.blue),
            onPressed: onToolsPressed,
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'file_button',
            mini: true,
            backgroundColor: Colors.white,
            child: const Icon(Icons.folder, color: Colors.blue),
            onPressed: onFilePressed,
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'location_button',
            mini: true,
            backgroundColor: Colors.white,
            child: isLoadingLocation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.blue,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.my_location, color: Colors.blue),
            onPressed: onLocationPressed,
          ),
        ],
      ),
    );
  }
}
