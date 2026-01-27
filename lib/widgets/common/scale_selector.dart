import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScaleSelector extends StatelessWidget {
  final int currentScale;
  final Function(int) onScaleSelected;

  const ScaleSelector({
    super.key,
    required this.currentScale,
    required this.onScaleSelected,
  });

  static const List<int> _availableScales = [
    1000000,
    500000,
    250000,
    100000,
    50000,
    25000,
    10000,
    5000,
    2500,
    1000,
  ];

  String _formatScale(int scale) {
    final formatter = NumberFormat.decimalPattern('es_PE');
    return '1:${formatter.format(scale)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showScaleDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatScale(currentScale),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Arial',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black87),
          ],
        ),
      ),
    );
  }

  void _showScaleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
          backgroundColor: Colors.white,
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 450),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Seleccionar Escala',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF37474F),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _availableScales.length,
                    itemBuilder: (context, index) {
                      final scale = _availableScales[index];
                      final isSelected = _isScaleSimilar(scale, currentScale);

                      return InkWell(
                        onTap: () {
                          onScaleSelected(scale);
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          color: isSelected
                              ? Colors.blue.withOpacity(0.08)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 24),
                          child: Row(
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 20,
                                color: isSelected
                                    ? Colors.blue[700]
                                    : Colors.grey[400],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _formatScale(scale),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.blue[800]
                                        : Colors.black87,
                                    fontFamily: 'Arial',
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    size: 20, color: Colors.blue[700]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to highlight if current scale is close to one of the presets
  bool _isScaleSimilar(int preset, int current) {
    // Allow some tolerance or exact match? 
    // Usually user selects a preset, map zooms to it. 
    // But if user zooms manually, scale might be 1:24999.
    // Let's say 10% tolerance? Or just exact if we snapped.
    // For UI highlighting, exact match or very close is better.
    // Let's use exact match for now, or 5% tolerance.
    final diff = (preset - current).abs();
    return diff < (preset * 0.05); 
  }
}