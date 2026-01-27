import 'package:flutter/material.dart';

class DrawingTools extends StatefulWidget {
  final Function(String) onDrawingToolSelected;
  final VoidCallback onSaveDrawings;
  final VoidCallback onEraseLastDrawing; // Agregar esta línea

  const DrawingTools({
    Key? key,
    required this.onDrawingToolSelected,
    required this.onSaveDrawings,
    required this.onEraseLastDrawing, // Agregar esta línea
  }) : super(key: key);

  @override
  State<DrawingTools> createState() => _DrawingToolsState();
}

class _DrawingToolsState extends State<DrawingTools>
    with SingleTickerProviderStateMixin {
  bool showDrawingTools = false;
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  bool isLineActive = false;
  bool isPolygonActive = false;
  bool isPointActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.5, 0), // Aparece desde la derecha
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleDrawingTools() {
    setState(() {
      showDrawingTools = !showDrawingTools;
      if (showDrawingTools) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.0, right: 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDrawingTools)
            SlideTransition(
              position: _slideAnimation,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: showDrawingTools ? 1.0 : 0.0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToolButton('line', Icons.timeline),
                      _buildToolButton('polygon', Icons.pentagon_outlined),
                      _buildToolButton('point', Icons.circle),
                      _buildToolButton('erase', Icons.arrow_back_sharp),
                      //_buildToolButton('save', Icons.save),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'toggle_drawing',
            onPressed: _toggleDrawingTools,
            backgroundColor: Colors.teal,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  showDrawingTools ? Icons.close : Icons.edit,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Dibujar',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(String toolKey, IconData iconData) {
    bool isActive = false;
    switch (toolKey) {
      case 'line':
        isActive = isLineActive;
        break;
      case 'polygon':
        isActive = isPolygonActive;
        break;
      case 'point':
        isActive = isPointActive;
        break;
    }

    bool anyToolActive = isLineActive || isPolygonActive || isPointActive;

    String label = '';
    switch (toolKey) {
      case 'line':
        label = 'Línea';
        break;
      case 'polygon':
        label = 'Polígono';
        break;
      case 'point':
        label = 'Punto';
        break;
      case 'erase':
        label = 'Borrar';
        break;
      // case 'save':
      //   label = 'Guardar';
      //   break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'draw_$toolKey',
          onPressed: toolKey == 'erase' && !anyToolActive
              ? null
              : () {
                  if (toolKey == 'erase') {
                    widget.onEraseLastDrawing();
                    return;
                  }
                  if (toolKey == 'save') {
                    widget.onSaveDrawings();
                    return;
                  }

                  setState(() {
                    isLineActive = false;
                    isPolygonActive = false;
                    isPointActive = false;

                    switch (toolKey) {
                      case 'line':
                        isLineActive = !isActive;
                        break;
                      case 'polygon':
                        isPolygonActive = !isActive;
                        break;
                      case 'point':
                        isPointActive = !isActive;
                        break;
                    }
                  });

                  widget.onDrawingToolSelected(toolKey);
                },
          backgroundColor: toolKey == 'erase' && !anyToolActive
              ? Colors.grey
              : isActive
                  ? Colors.grey.shade800
                  : Colors.teal.withOpacity(0.8),
          mini: true,
          child: Icon(
            isActive && toolKey != 'save' ? Icons.close : iconData,
            color: toolKey == 'erase' && !anyToolActive
                ? Colors.white.withOpacity(0.5)
                : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
