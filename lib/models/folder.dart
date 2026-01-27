import 'package:flutter/material.dart';

class Folder {
  final String id;
  final String name;
  // Eliminado: final String? parentId; // ID de la carpeta padre, null si es raíz
  final DateTime createdAt;
  final Color color;
  
  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.color = Colors.blue,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'color': color.value,
    };
  }
  
  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      color: Color(json['color'] as int),
    );
  }
}