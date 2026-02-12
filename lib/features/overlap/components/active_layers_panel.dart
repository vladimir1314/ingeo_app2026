import 'dart:io';
import 'package:flutter/material.dart';

import 'package:ingeo_app/widgets/active_layers/intersection_controls.dart';
import 'package:ingeo_app/widgets/common/error_display.dart';
import 'package:ingeo_app/widgets/common/loading_overlay.dart';

import 'package:share_plus/share_plus.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';

import 'package:ingeo_app/models/wms_layer.dart';

import 'package:ingeo_app/models/intersection_result.dart';
import 'package:ingeo_app/services/geoserver_service.dart';
import 'package:ingeo_app/services/kmz_export_service.dart';
import 'package:ingeo_app/services/pdf_report_service.dart';
import 'package:ingeo_app/services/intersection_service.dart';

class ActiveLayersPanel extends StatefulWidget {
  final bool isVisible;
  final VoidCallback onClose;
  final Map<String, bool> layerStates;
  final List<LayerGroup> layerGroups;
  final List<SavedDrawingLayer> savedLayers;
  final void Function(String, bool) onLayerToggle;
  final Function(WmsLayer)? onWmsLayerAdd;
  final Function(SavedDrawingLayer)? onSaveGeometry;
  final Function(SavedDrawingLayer)? onIntersectionResult;

  const ActiveLayersPanel({
    super.key,
    required this.isVisible,
    required this.onClose,
    required this.layerStates,
    required this.layerGroups,
    required this.savedLayers,
    required this.onLayerToggle,
    this.onWmsLayerAdd,
    this.onSaveGeometry,
    this.onIntersectionResult,
  });

  @override
  State<ActiveLayersPanel> createState() => _ActiveLayersPanelState();
}

class _ActiveLayersPanelState extends State<ActiveLayersPanel> {
  late final TextEditingController _nameController;
  late final GeoserverService _geoService;
  late final KmzExportService _kmzService;
  late final PdfReportService _pdfService;
  late final IntersectionService _intersectionService;

  IntersectionResult _currentResult = IntersectionResult.idle();
  
  OverlayEntry? _overlayEntry;
  final ValueNotifier<double?> _progressNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _geoService = GeoserverService();
    _kmzService = KmzExportService();
    _pdfService = PdfReportService(widget.layerGroups);
    _intersectionService = IntersectionService(_geoService);
  }

  @override
  void dispose() {
    _hideOverlay();
    _nameController.dispose();
    _geoService.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _generateIntersection() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Por favor, ingresa un nombre', isError: true);
      return;
    }

    _showOverlay('Procesando intersección...');
    setState(() {
      _currentResult = IntersectionResult.loading();
    });

    try {
      // Obtener capas activas
      final activeDrawingLayers = _getActiveDrawingLayers();
      final activeThematicLayers = _getActiveThematicLayers();

      if (activeDrawingLayers.isEmpty || activeThematicLayers.isEmpty) {
        _hideOverlay();
        setState(() {
          _currentResult = IntersectionResult.error(
            'Se requieren capas de dibujo y capas temáticas activas',
          );
        });
        return;
      }

      // Ejecutar intersección
      final results = await _intersectionService.performIntersection(
        drawingLayers: activeDrawingLayers,
        thematicLayers: activeThematicLayers,
        onProgress: (progress) {
          _progressNotifier.value = progress;
          setState(() {
            _currentResult = IntersectionResult.processing(progress);
          });
        },
      );

      if (results.isEmpty) {
        _hideOverlay();
        setState(() {
          _currentResult = IntersectionResult.error(
            'No se encontraron intersecciones geométricas',
          );
        });
        return;
      }

      // Generar archivos
      final kmzFile = await _kmzService.exportToKmz(results, name);
      final pdfFile = await _pdfService.generateReport(
        results: results,
        drawingLayers: activeDrawingLayers,
        thematicLayers: activeThematicLayers,
        queryCode: name,
      );

      // Crear capa de resultado
      final resultLayer = _intersectionService.createLayerFromResults(
        results,
        name,
      );

      if (widget.onIntersectionResult != null) {
        widget.onIntersectionResult!(resultLayer);
      }

      _hideOverlay();
      setState(() {
        _currentResult = IntersectionResult.success(
          files: [kmzFile, pdfFile],
          layer: resultLayer,
          kmzPath: kmzFile.path,
          pdfPath: pdfFile.path,
        );
      });

      // Compartir archivos
      await Share.shareXFiles([
        XFile(kmzFile.path),
        XFile(pdfFile.path),
      ], subject: 'Intersecciones geométricas - $name');
    } catch (e, stackTrace) {
      debugPrint('Error en intersección: $e\n$stackTrace');
      _hideOverlay();
      setState(() {
        _currentResult = IntersectionResult.error(e.toString());
      });
    }
  }

  void _showOverlay(String message) {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<double?>(
        valueListenable: _progressNotifier,
        builder: (context, progress, child) {
          return Material(
            color: Colors.transparent,
            child: LoadingOverlay(
              message: message,
              progress: progress,
            ),
          );
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _progressNotifier.value = null;
  }

  List<SavedDrawingLayer> _getActiveDrawingLayers() {
    return widget.layerStates.entries
        .where((e) => e.value && e.key.startsWith('saved_layer_'))
        .map((e) => widget.savedLayers.firstWhere((l) => l.id == e.key))
        .toList();
  }

  List<String> _getActiveThematicLayers() {
    return widget.layerStates.entries
        .where((e) => e.value && e.key.startsWith('sp_'))
        .map((e) => e.key)
        .toList();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: widget.isVisible ? 0 : -MediaQuery.of(context).size.width * 0.8,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.8,
      child: Material(
        elevation: 8,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(),
              const Divider(height: 1),
              Expanded(child: _buildLayerList()),
              if (_currentResult.hasError)
                ErrorDisplay(
                  message: _currentResult.errorMessage!,
                  onRetry: () => setState(
                    () => _currentResult = IntersectionResult.idle(),
                  ),
                ),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
          const SizedBox(width: 8),
          const Text(
            'Capas Activas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          ..._buildLayerGroups(),
          if (_shouldShowDrawingsDivider()) _buildDrawingsDivider(),
          if (_hasActiveDrawings()) _buildDrawingsSection(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final activeCount = widget.layerStates.values.where((v) => v).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.layers, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            'Capas Activas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$activeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLayerGroups() {
    return widget.layerGroups.map((group) {
      final activeItems = group.items
          .where((item) => widget.layerStates[item.layerId] == true)
          .toList();

      if (activeItems.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroupHeader(group, activeItems.length),
            ...activeItems.asMap().entries.map((entry) {
              return _buildLayerItem(
                entry.value,
                isLast: entry.key == activeItems.length - 1,
              );
            }),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGroupHeader(LayerGroup group, int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 8),
          Text(
            group.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerItem(LayerItem item, {required bool isLast}) {
    return Container(
      decoration: BoxDecoration(
        border: !isLast
            ? Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
              )
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.green.shade400,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        trailing: Icon(
          Icons.visibility,
          color: Colors.green.shade600,
          size: 18,
        ),
      ),
    );
  }

  bool _shouldShowDrawingsDivider() {
    final hasThematic = widget.layerGroups.any(
      (g) => g.items.any((i) => widget.layerStates[i.layerId] == true),
    );
    final hasDrawings = _hasActiveDrawings();
    return hasThematic && hasDrawings;
  }

  bool _hasActiveDrawings() {
    return widget.savedLayers.any((l) => widget.layerStates[l.id] == true);
  }

  Widget _buildDrawingsDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'DIBUJOS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _buildDrawingsSection() {
    final activeDrawings = widget.savedLayers
        .where((l) => widget.layerStates[l.id] == true)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: activeDrawings.asMap().entries.map((entry) {
          final layer = entry.value;
          final isLast = entry.key == activeDrawings.length - 1;
          return _buildDrawingItem(layer, isLast: isLast);
        }).toList(),
      ),
    );
  }

  Widget _buildDrawingItem(SavedDrawingLayer layer, {required bool isLast}) {
    return Container(
      decoration: BoxDecoration(
        border: !isLast
            ? Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
              )
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.draw, color: Colors.orange.shade600, size: 16),
        ),
        title: Text(
          layer.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _getLayerInfo(layer),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.visibility,
          color: Colors.orange.shade600,
          size: 18,
        ),
      ),
    );
  }

  String _getLayerInfo(SavedDrawingLayer layer) {
    final info = <String>[];
    if (layer.points.isNotEmpty) {
      info.add(
        '${layer.points.length} punto${layer.points.length != 1 ? 's' : ''}',
      );
    }
    if (layer.lines.isNotEmpty) {
      info.add(
        '${layer.lines.length} línea${layer.lines.length != 1 ? 's' : ''}',
      );
    }
    if (layer.polygons.isNotEmpty) {
      info.add(
        '${layer.polygons.length} polígono${layer.polygons.length != 1 ? 's' : ''}',
      );
    }
    return info.isEmpty ? 'Sin elementos' : info.join(', ');
  }

  Widget _buildBottomControls() {
    return IntersectionControls(
      controller: _nameController,
      activeLayersCount: widget.layerStates.values.where((v) => v).length,
      isProcessing: _currentResult.isLoading,
      onGenerate: _generateIntersection,
    );
  }
}
