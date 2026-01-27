import 'package:flutter/material.dart';

class MeasurementTools extends StatefulWidget {
  final Function(String) onMeasurementToolSelected;

  const MeasurementTools({
    Key? key,
    required this.onMeasurementToolSelected,
  }) : super(key: key);

  @override
  State<MeasurementTools> createState() => _MeasurementToolsState();
}

class _MeasurementToolsState extends State<MeasurementTools>
    with SingleTickerProviderStateMixin {
  bool showMeasurementTools = false;
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  String? selectedTool;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.5, 0),
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

  void _toggleMeasurementTools() {
    setState(() {
      showMeasurementTools = !showMeasurementTools;
      if (showMeasurementTools) {
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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'toggle_measurement',
            onPressed: _toggleMeasurementTools,
            backgroundColor: Colors.deepOrange,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  showMeasurementTools ? Icons.close : Icons.straighten,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Medir',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (showMeasurementTools)
            SlideTransition(
              position: _slideAnimation,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: showMeasurementTools ? 1.0 : 0.0,
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
                      _buildToolButton('measure_line', Icons.linear_scale),
                      _buildToolButton('measure_area', Icons.square_foot),
                      _buildToolButton(
                          'measure_radius', Icons.radio_button_unchecked),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolButton(String toolKey, IconData iconData) {
    final isSelected = selectedTool == toolKey;

    return Row(
      children: [
        FloatingActionButton.small(
          heroTag: toolKey,
          onPressed: () {
            setState(() {
              if (isSelected) {
                selectedTool = null;
                widget.onMeasurementToolSelected(
                    'finalizar_medicion'); // Deselección
              } else {
                selectedTool = toolKey;
                widget.onMeasurementToolSelected(toolKey);
              }
            });
          },
          backgroundColor: isSelected
              ? Colors.grey.shade800
              : Colors.deepOrange.withOpacity(0.7),
          child: Icon(
            isSelected ? Icons.close : iconData,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
