import 'dart:io';
import 'package:ingeo_app/models/saved_drawing_layer.dart';

enum IntersectionStatus {
  idle,
  loading,
  validating,
  processing,
  success,
  error,
  cancelled,
}

class IntersectionResult {
  final IntersectionStatus status;
  final List<File>? files;
  final String? kmzPath;
  final String? pdfPath;
  final String? errorMessage;
  final SavedDrawingLayer? resultLayer;
  final double? progress;
  final DateTime? startTime;
  final DateTime? endTime;

  const IntersectionResult._({
    required this.status,
    this.files,
    this.kmzPath,
    this.pdfPath,
    this.errorMessage,
    this.resultLayer,
    this.progress,
    this.startTime,
    this.endTime,
  });

  factory IntersectionResult.idle() =>
      const IntersectionResult._(status: IntersectionStatus.idle);

  factory IntersectionResult.loading() =>
      const IntersectionResult._(status: IntersectionStatus.loading);

  factory IntersectionResult.processing(double progress) =>
      IntersectionResult._(
        status: IntersectionStatus.processing,
        progress: progress,
      );

  factory IntersectionResult.success({
    required List<File> files,
    required SavedDrawingLayer layer,
    String? kmzPath,
    String? pdfPath,
  }) => IntersectionResult._(
    status: IntersectionStatus.success,
    files: files,
    resultLayer: layer,
    kmzPath: kmzPath,
    pdfPath: pdfPath,
    endTime: DateTime.now(),
  );

  factory IntersectionResult.error(String message) => IntersectionResult._(
    status: IntersectionStatus.error,
    errorMessage: message,
    endTime: DateTime.now(),
  );

  bool get isLoading =>
      status == IntersectionStatus.loading ||
      status == IntersectionStatus.processing;
  bool get isSuccess => status == IntersectionStatus.success;
  bool get hasError => status == IntersectionStatus.error;

  Duration? get duration {
    if (startTime == null || endTime == null) return null;
    return endTime!.difference(startTime!);
  }
}
