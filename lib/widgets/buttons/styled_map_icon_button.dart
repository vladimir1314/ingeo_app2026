// styled_map_icon_button.dart
import 'package:flutter/material.dart';

class StyledMapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const StyledMapIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.teal, size: 26),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
