import 'package:flutter/material.dart';

class MenuButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;
  final double? width;
  final double? fontSize;

  const MenuButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.color,
    this.width = 100,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.6),
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize),
        ),
      ),
    );
  }
}
