import 'package:flutter/material.dart';

class FileSelector extends StatelessWidget {
  final Function() onImport;
  final Function() onExport;

  const FileSelector({
    super.key,
    required this.onImport,
    required this.onExport,
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
          _FileOption(
            title: 'Importar KML',
            icon: Icons.upload_file,
            onTap: onImport,
          ),
          const Divider(height: 1),
          _FileOption(
            title: 'Exportar KML',
            icon: Icons.download,
            onTap: onExport,
          ),
        ],
      ),
    );
  }
}

class _FileOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _FileOption({
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