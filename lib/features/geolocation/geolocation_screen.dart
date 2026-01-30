import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/folder.dart';
import 'package:ingeo_app/models/geometry_data.dart';
import 'package:ingeo_app/models/labeled_marker.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/models/wms_layer.dart';
import 'package:ingeo_app/features/geolocation/components/drawing_tools.dart';

import 'package:ingeo_app/features/geolocation/components/drawings_layer_selector.dart';
import 'package:ingeo_app/features/geolocation/components/measurement_tools.dart';
import 'package:ingeo_app/features/geolocation/components/wms_feature_info.dart';

import 'package:ingeo_app/features/geolocation/components/wms_layer_selector.dart';
import 'package:ingeo_app/utils/export_layers.dart';
import 'package:ingeo_app/utils/import_layers.dart';
import 'package:ingeo_app/utils/pdf_report_generator.dart';
import 'package:ingeo_app/widgets/buttons/menu_button.dart';
import 'package:ingeo_app/widgets/buttons/styled_map_icon_button.dart';
import 'package:ingeo_app/widgets/common/scale_selector.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ingeo_app/features/geolocation/models/label_input_result.dart';
import 'package:ingeo_app/features/geolocation/components/search_bar.dart';
import 'package:utm/utm.dart';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'components/base_map_selector.dart';

import 'package:share_plus/share_plus.dart';

import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ingeo_app/core/services/elevation_service.dart';
import 'package:ingeo_app/utils/pending_file_handler.dart';
import 'package:ingeo_app/core/access_control/access_control_service.dart';
import 'package:ingeo_app/core/access_control/app_features.dart';
import 'package:ingeo_app/data/layers/layer_repository.dart';
import 'package:ingeo_app/features/auth/login_screen.dart';
import 'package:ingeo_app/features/geolocation/components/label_input_modal.dart';

class GeolocationScreen extends StatefulWidget {
  const GeolocationScreen({super.key});

  @override
  State<GeolocationScreen> createState() => _GeolocationScreenState();
}

class _GeolocationScreenState extends State<GeolocationScreen> {
  String currentMapType = 'osm';
  bool showMapSelector = false;
  bool showToolsSelector = false;
  bool showFileSelector = false;
  bool isMeasuringDistance = false;
  bool _isExpanded = false;
  List<LatLng> measurePoints = [];
  LatLng currentPosition = const LatLng(-12.0464, -77.0428);
  List<Folder> folders = [];

  // Obtener carpetas guardadas
  List<Folder> _getFolders() {
    return folders;
  }

  final GlobalKey mapKey = GlobalKey();

  final MapController mapController = MapController();
  bool isLoadingLocation = false;
  bool showLocationMarker = false;
  LatLng centerPosition = const LatLng(-9.7786, -74.9463);

  bool isDrawingPoint = false;
  // List<Marker> drawnPoints = [];
  List<LabeledMarker> drawnPoints = [];
  // List<Polyline> drawnLines = [];
  List<LabeledPolyline> drawnLines = [];
  bool isDrawingLine = false;
  List<LatLng> linePoints = [];
  bool isDrawingPolygon = false;
  List<LatLng> polygonPoints = [];
  List<LabeledPolygon> drawnPolygons = [];
  bool isDrawingRadius = false;
  LatLng? radiusCenter;
  List<Marker> centerMarkers = [];
  double radiusInKm = 1.0;

  List<Marker> drawnCircles = [];

  bool showWmsLayerSelector = false;
  bool showSavedDrawings = false;
  List<SavedDrawingLayer> savedLayers = [];
  List<WmsLayer> wmsLayers = [];
  StreamSubscription<Position>? _positionStreamSubscription;

  bool isTracking = false;
  List<LatLng> trackPoints = [];
  StreamSubscription<Position>? _trackingSubscription;

  bool showGeometryPanel = false;
  dynamic selectedGeometry;

  LatLng? currentTrackingPosition;
  double? currentAccuracy = 0;
  int? currentElevation;

  bool isMenuVisible = true;

  String get mapUrlTemplate {
    switch (currentMapType) {
      case 'satellite':
        return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case 'hybrid':
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case 'hybrid_no_labels':
        return 'https://mt1.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}';
      case 'terrain':
        return 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case 'google_maps':
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeLayers();
    loadWmsLayers();
    _getCurrentAccuracy();
    _updateElevation();
    loadFolders(); // Cargar las carpetas guardadas
    _loadMapConfig();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingFile();
      PendingFileHandler().pendingFilePath.addListener(_checkPendingFile);
    });
  }

  @override
  void dispose() {
    PendingFileHandler().pendingFilePath.removeListener(_checkPendingFile);
    _positionStreamSubscription?.cancel();

    _trackingSubscription?.cancel();
    super.dispose();
  }

  void _checkPendingFile() {
    final path = PendingFileHandler().pendingFilePath.value;
    if (path != null && mounted) {
      PendingFileHandler().clear();
      _importPendingFile(path);
    }
  }

  Future<void> _importPendingFile(String path) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Importando archivo...'),
                ],
              ),
            ),
          ),
        ),
      );

      final layer = await ImportLayersUtil.importKmlOrKmzFromPath(path);

      if (mounted) {
        Navigator.of(context).pop();
      }

      if (layer != null && mounted) {
        setState(() {
          savedLayers.add(layer);
          layerStates[layer.id] = true;
        });
        await saveLayers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${layer.name} importado correctamente'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Ver detalles',
                textColor: Colors.white,
                onPressed: () {
                  ImportLayersUtil.showFileAttributes(
                    context,
                    layer.attributes ?? {},
                  );
                },
              ),
            ),
          );
        }

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            handleLayerFocus(layer.id);
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron elementos válidos en el archivo'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Asegurarse de cerrar el diálogo si sigue abierto (comprobación básica)
        // Nota: Si el diálogo ya se cerró, pop podría cerrar la pantalla actual.
        // Lo ideal es tener una referencia al diálogo o usar una variable de estado,
        // pero por simplicidad asumimos que si falló en importKmlOrKmzFromPath, el diálogo sigue ahí.
        // Una forma más segura es intentar cerrar solo si sabemos que está abierto,
        // pero Navigator.pop sin contexto específico es riesgoso.
        // Asumimos que el diálogo se cierra en el bloque try antes de verificar layer.
        // Si falla antes, cae aquí.
        Navigator.of(context).maybePop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeLayers() async {
    await loadLayers();
  }

  Future<void> _updateElevation() async {
    try {
      final elev = await ElevationService.fetchElevation(
        centerPosition.latitude,
        centerPosition.longitude,
      );
      if (mounted) {
        setState(() {
          currentElevation = elev;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMapConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedType = prefs.getString('map_type');
      final lat = prefs.getDouble('map_center_lat');
      final lng = prefs.getDouble('map_center_lng');
      final zoom = prefs.getDouble('map_zoom');
      if (savedType != null) {
        setState(() {
          currentMapType = savedType;
        });
      }
      if (lat != null && lng != null && zoom != null) {
        final pos = LatLng(lat, lng);
        setState(() {
          centerPosition = pos;
        });
        try {
          mapController.move(pos, zoom);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _saveMapConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('map_type', currentMapType);
      await prefs.setDouble('map_center_lat', centerPosition.latitude);
      await prefs.setDouble('map_center_lng', centerPosition.longitude);
      await prefs.setDouble('map_zoom', mapController.zoom);
    } catch (_) {}
  }

  void toggleMapSelector() {
    setState(() {
      showMapSelector = !showMapSelector;
      if (showMapSelector) {
        showToolsSelector = false;
        showFileSelector = false;
      }
    });
  }

  void toggleWmsLayerSelector() {
    setState(() {
      showWmsLayerSelector = !showWmsLayerSelector;
      if (showWmsLayerSelector) {
        showMapSelector = false;
        showToolsSelector = false;
        showFileSelector = false;
      }
    });
  }

  void toggleToolsSelector() {
    setState(() {
      showToolsSelector = !showToolsSelector;
      if (showToolsSelector) {
        showMapSelector = false;
        showFileSelector = false;
      }
    });
  }

  void toggleFileSelector() {
    setState(() {
      importFile();

      showMapSelector = false;
    });
  }

  void changeMapType(String type) {
    setState(() {
      currentMapType = type;
      showMapSelector = false;
    });
    _saveMapConfig();
  }

  void _onLocationSelected(LatLng location) {
    mapController.move(location, 15.0);
    _saveMapConfig();
  }

  void startMeasureDistance() {
    setState(() {
      isMeasuringDistance = true;
      measurePoints = [];
      showToolsSelector = false;
    });
  }

  void orientToNorth() {
    mapController.rotate(0.0);
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    final RenderBox box =
        mapKey.currentContext?.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(tapPosition.global);
    if (isMeasuringDistance) {
      setState(() {
        measurePoints.add(centerPosition);
      });
    } else if (isDrawingPoint) {
      setState(() {
        drawnPoints.add(
          LabeledMarker(
            marker: Marker(
              point: centerPosition,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            label: '',
            geometry: GeometryData(name: '', type: 'Point', coordinates: []),
            // puedes dejarlo vacío o asignar una etiqueta si ya la tienes
          ),
        );
      });
      _showLabelInputModal('point');
    } else if (isDrawingLine) {
      setState(() {
        linePoints.add(centerPosition);
      });
    } else if (isDrawingPolygon) {
      setState(() {
        polygonPoints.add(centerPosition);
      });
    } else if (isDrawingRadius && radiusCenter == null) {
      setState(() {
        centerMarkers.clear(); // Limpiar marcadores anteriores
        centerMarkers.add(
          Marker(
            point: centerPosition,
            width: 20,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        );
        radiusCenter = centerPosition;
        _showRadiusInput();
      });
    }
    if (layerStates.entries.any(
      (entry) => entry.value && entry.key.startsWith('sp_'),
    )) {
      WmsFeatureInfo.getFeatureInfo(
        context: context,
        mapController: mapController,
        layerStates: layerStates,
        tapXY: localOffset,
        viewportSize: box.size,
        point: point,
      );
    }
  }

  double _calculateDistance() {
    if (measurePoints.length < 2) return 0;

    final Distance distance = Distance();
    double totalDistance = 0;

    for (int i = 0; i < measurePoints.length - 1; i++) {
      totalDistance += distance.as(
        LengthUnit.Meter,
        measurePoints[i],
        measurePoints[i + 1],
      );
    }

    return totalDistance;
  }

  // Función para calcular el área de un polígono usando la fórmula del área de Gauss
  double calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0;

    double area = 0;
    for (int i = 0; i < points.length - 1; i++) {
      area +=
          (points[i].longitude * points[i + 1].latitude) -
          (points[i + 1].longitude * points[i].latitude);
    }

    // Completar el polígono con el último y primer punto
    area +=
        (points.last.longitude * points.first.latitude) -
        (points.first.longitude * points.last.latitude);

    // El área en grados cuadrados, convertir a metros cuadrados
    area = (area.abs() / 2) * 111319.9 * 111319.9;
    return area;
  }

  double calculatePolygonPerimeter(List<LatLng> points) {
    if (points.length < 2) return 0;

    final distance = Distance();
    double perimeter = 0;

    for (int i = 0; i < points.length - 1; i++) {
      perimeter += distance(points[i], points[i + 1]);
    }

    // Cerrar el polígono (último punto al primero)
    perimeter += distance(points.last, points.first);

    return perimeter; // en metros
  }

  void toggleTracking() async {
    if (isLoadingLocation) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Ubicación activa'),
          content: const Text(
            'Para comenzar el tracking, primero debes desactivar la ubicación en tiempo real.',
            textAlign: TextAlign.justify,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desactivar ubicación'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _positionStreamSubscription?.cancel();
        setState(() {
          isLoadingLocation = false;
          showLocationMarker = false;
        });
      } else {
        return;
      }
    }
    if (!isTracking) {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Validar que el permiso sea "siempre"
      if (permission != LocationPermission.always) {
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Permiso requerido'),
              ],
            ),
            content: const Text(
              'Para registrar tu recorrido incluso cuando la app esté en segundo plano, '
              'necesitamos que otorgues el permiso de ubicación "Permitir siempre". '
              'Sin este permiso, el tracking se detendrá cuando cierres o minimices la app.\n\n'
              '¿Deseas ir a configuración para activarlo?',
              textAlign: TextAlign.justify,
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                label: const Text('Ir a configuración'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await Geolocator.openAppSettings();
        }

        return;
      }

      // ✅ Obtener ubicación actual
      final currentPosition = await Geolocator.getCurrentPosition();

      // ✅ Centrar y hacer zoom en el mapa
      mapController.move(
        LatLng(currentPosition.latitude, currentPosition.longitude),
        17.0, // Puedes ajustar el nivel de zoom
      );

      // Permiso válido, iniciar tracking
      setState(() {
        isTracking = true;
        trackPoints = [];
        isMeasuringDistance = false;
        isDrawingPoint = false;
        isDrawingLine = false;
        isDrawingPolygon = false;
        isDrawingRadius = false;
        linePoints.clear();
        polygonPoints.clear();
      });

      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500),
      );

      _trackingSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              if (mounted && isTracking) {
                final newPos = LatLng(position.latitude, position.longitude);

                setState(() {
                  currentTrackingPosition = newPos;
                  trackPoints.add(newPos);
                  mapController.move(newPos, mapController.zoom);
                });
              }
            },
            onError: (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error en el tracking: $e')),
                );
              }
            },
          );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracking iniciado en segundo plano'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(top: 20, left: 16, right: 16),
        ),
      );
    } else {
      // Detener tracking
      await _trackingSubscription?.cancel();
      setState(() {
        currentTrackingPosition = null;
      });
      _showTrackLabelInput();
    }
  }

  void _showTrackLabelInput() {
    String trackName = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 12,
          ),
          child: Wrap(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Guardar Track',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => trackName = value,
                      decoration: const InputDecoration(
                        hintText: 'Nombre del track',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              isTracking = false;
                              trackPoints = [];
                              isMeasuringDistance = false;
                              isDrawingPoint = false;
                              isDrawingLine = false;
                              isDrawingPolygon = false;
                              isDrawingRadius = false;
                              linePoints.clear();
                              polygonPoints.clear();
                            });
                          },
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (trackPoints.isNotEmpty) {
                              // Crear un marcador para el inicio del track
                              final startMarker = LabeledMarker(
                                marker: Marker(
                                  point: trackPoints.first,
                                  width: 20,
                                  height: 20,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                label:
                                    '${trackName.isNotEmpty ? trackName : 'Track'} - Inicio',
                                geometry: GeometryData(
                                  name: '',
                                  type: 'Point',
                                  coordinates: [],
                                ),
                              );

                              final track = SavedDrawingLayer(
                                id: 'saved_track_${DateTime.now().millisecondsSinceEpoch}',
                                name: trackName.isNotEmpty
                                    ? trackName
                                    : 'Track ${savedLayers.length + 1}',
                                lines: [
                                  LabeledPolyline(
                                    polyline: Polyline(
                                      points: trackPoints,
                                      color: Colors.blue,
                                      strokeWidth: 3.0,
                                    ),
                                    label: trackName,
                                  ),
                                ],
                                polygons: [],
                                points: [startMarker],
                                rawGeometries: [],
                                timestamp: DateTime.now(),
                              );

                              setState(() {
                                savedLayers.add(track);
                                isTracking = false;
                                trackPoints = [];
                                isMeasuringDistance = false;
                                isDrawingPoint = false;
                                isDrawingLine = false;
                                isDrawingPolygon = false;
                                isDrawingRadius = false;
                                linePoints.clear();
                                polygonPoints.clear();
                                // Activar el track en layerStates para que aparezca inmediatamente en WmsLayerSelector
                                layerStates[track.id] = true;
                              });
                              saveLayers();
                            }
                            Navigator.of(context).pop();
                          },
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    if (isTracking) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Tracking activo'),
          content: const Text(
            'Para activar la ubicación en tiempo real, primero debes detener el tracking.',
            textAlign: TextAlign.justify,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Detener tracking'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _trackingSubscription?.cancel();

        _showTrackLabelInput();
        return;
      } else {
        return;
      }
    }
    if (isLoadingLocation) {
      // Desactivar seguimiento
      await _positionStreamSubscription?.cancel();
      setState(() {
        isLoadingLocation = false;
        showLocationMarker = false;
      });
    } else {
      setState(() {
        isLoadingLocation = true;
      });

      try {
        // Verificar permisos
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw 'Permisos de ubicación denegados';
          }
        }

        // Cancelar la suscripción anterior si existe
        await _positionStreamSubscription?.cancel();

        // Configurar el stream de ubicación
        final locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 500),
        );

        // Suscribirse al stream de ubicación
        _positionStreamSubscription =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen(
              (Position position) {
                setState(() {
                  currentPosition = LatLng(
                    position.latitude,
                    position.longitude,
                  );
                  mapController.move(currentPosition, mapController.zoom);
                  showLocationMarker = true;
                });
              },
              onError: (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al actualizar ubicación: $e')),
                );
              },
            );

        // Obtener posición inicial
        Position position = await Geolocator.getCurrentPosition();
        setState(() {
          currentPosition = LatLng(position.latitude, position.longitude);
          centerPosition = LatLng(position.latitude, position.longitude);

          mapController.move(currentPosition, 15.0);
          showLocationMarker = true;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
      } finally {}
    }
  }

  // Add this method to your _GeolocationScreenState class
  String _getUTMCoordinates(LatLng position) {
    final utmResult = UTM.fromLatLon(
      lat: position.latitude,
      lon: position.longitude,
    );
    return '${utmResult.easting.round()}E  ${utmResult.northing.round()}N  ${utmResult.zoneNumber}${utmResult.zoneLetter}';
  }

  // Método para obtener la ubicación con precisión
  Future<void> _getCurrentAccuracy() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Guardamos precisión
    setState(() {
      currentAccuracy = position.accuracy;

      print("Precisión: $currentAccuracy metros");
    });
  }

  void onGeometryTap(dynamic geometry) {
    setState(() {
      selectedGeometry = geometry;
      showGeometryPanel = true;
    });
  }

  void _onMapMoved() {
    setState(() {
      centerPosition = mapController.center;
      if (isDrawingRadius && radiusCenter != null) {
        drawnCircles.clear();
        _drawCircle(); // Redibujar el círculo cuando el mapa se mueve
      }
    });
    _updateElevation();
    _saveMapConfig();
  }

  final Map<String, bool> layerStates = {
    'sp_comunidades_campesinas': false,
    'sp_comunidades_nativas': false,
    'sp_departamentos': false,
    'sp_distritos': false,
    'sp_provincias': false,
    'sp_grilla_utm_peru': false,
    'sp_cuencas': false,
    'sp_subcuencas': false,
    'sp_lagunas': false,
  };

  final List<LayerGroup> layerGroups = LayerRepository.all;

  List<Widget> getWmsTileLayers() {
    const baseUrl = 'http://84.247.176.139:8080/geoserver/ingeo/wms?';

    return layerStates.entries
        .where((entry) => entry.value && entry.key.startsWith('sp_'))
        .map(
          (entry) => TileLayer(
            key: ValueKey('sp_${entry.key}'),
            wmsOptions: WMSTileLayerOptions(
              baseUrl: baseUrl,
              layers: ['ingeo:${entry.key}'],
              format: 'image/png',
              transparent: true,
              version: '1.1.0',
              styles: const [''],
              otherParameters: const {'srs': 'EPSG:3857'},
            ),
          ),
        )
        .toList();
  }

  // Modificar el método _handleAddWmsLayer para usar el nuevo modelo
  void _handleAddWmsLayer(Map<String, dynamic> wmsLayer) {
    final layerId = 'wms_layer_${DateTime.now().millisecondsSinceEpoch}';
    final newLayer = WmsLayer(
      id: layerId,
      name: wmsLayer['title'],
      url: wmsLayer['url'],
      layerName: wmsLayer['name'],
      timestamp: DateTime.now(),
    );

    setState(() {
      wmsLayers.add(newLayer);
      layerStates[layerId] = true;
    });

    saveWmsLayers(); // Guardar las capas WMS
  }

  // Añadir métodos para guardar y cargar capas WMS
  Future<void> saveWmsLayers() async {
    final prefs = await SharedPreferences.getInstance();
    final layersJson = wmsLayers.map((layer) => layer.toJson()).toList();
    await prefs.setString('wms_layers', jsonEncode(layersJson));
  }

  Future<void> loadWmsLayers() async {
    final prefs = await SharedPreferences.getInstance();
    final layersString = prefs.getString('wms_layers');
    if (layersString != null) {
      final layersJson = jsonDecode(layersString) as List;
      setState(() {
        wmsLayers = layersJson.map((json) => WmsLayer.fromJson(json)).toList();
        // Inicializar los estados de las capas cargadas
        for (var layer in wmsLayers) {
          layerStates[layer.id] = layer.isVisible; // Usar el estado guardado
        }
      });
    }
  }

  void toggleLayer(String layerId, bool value) {
    setState(() {
      layerStates[layerId] = value;
      // Actualizar el estado en el modelo WmsLayer si corresponde
      if (layerId.startsWith('wms_layer_')) {
        final index = wmsLayers.indexWhere((layer) => layer.id == layerId);
        if (index >= 0) {
          final updatedLayer = WmsLayer(
            id: wmsLayers[index].id,
            name: wmsLayers[index].name,
            url: wmsLayers[index].url,
            layerName: wmsLayers[index].layerName,
            timestamp: wmsLayers[index].timestamp,
            isVisible: value,
          );
          wmsLayers[index] = updatedLayer;
          saveWmsLayers(); // Guardar el cambio de estado
        }
      }
    });
  }

  List<Widget> _buildWmsLayers() {
    List<Widget> layers = [];

    for (var layer in wmsLayers) {
      if (layerStates[layer.id] != true) continue;

      layers.add(
        TileLayer(
          key: ValueKey(layer.id),
          wmsOptions: WMSTileLayerOptions(
            baseUrl: layer.url,
            layers: [layer.layerName],
            format: 'image/png',
            transparent: true,
            version: '1.1.0',
            styles: const [''],
            otherParameters: const {'srs': 'EPSG:3857'},
          ),
        ),
      );
    }

    return layers;
  }

  void handleMeasurementToolSelected(String tool) {
    setState(() {
      switch (tool) {
        case 'measure_line':
          isMeasuringDistance = true;
          measurePoints = [];
          isDrawingPoint = false;
          isDrawingLine = false;
          isDrawingPolygon = false;
          isDrawingRadius = false;
          break;
        case 'measure_area':
          isMeasuringDistance = false;
          isDrawingPolygon = true;
          polygonPoints = [];
          isDrawingPoint = false;
          isDrawingLine = false;
          isDrawingRadius = false;
          break;
        case 'measure_radius':
          isDrawingRadius = true;
          radiusCenter = null;
          isMeasuringDistance = false;
          isDrawingPoint = false;
          isDrawingLine = false;
          isDrawingPolygon = false;
          break;
        case 'finalizar_medicion':
          // Limpiar todos los puntos y estados de medición
          measurePoints.clear();
          polygonPoints.clear();
          radiusCenter = null;
          drawnCircles.clear();
          isMeasuringDistance = false;
          isDrawingPolygon = false;
          isDrawingRadius = false;
          break;
      }
    });
  }

  Future<void> saveLayers() async {
    final prefs = await SharedPreferences.getInstance();
    final layersJson = savedLayers.map((layer) => layer.toJson()).toList();
    await prefs.setString('saved_layers', jsonEncode(layersJson));
  }

  Future<void> loadLayers() async {
    final prefs = await SharedPreferences.getInstance();
    final layersString = prefs.getString('saved_layers');
    if (layersString != null) {
      final layersJson = jsonDecode(layersString) as List;
      setState(() {
        savedLayers = layersJson
            .map((json) => SavedDrawingLayer.fromJson(json))
            .toList();
        // Initialize states for loaded layers
        for (var layer in savedLayers) {
          if (layer.id.startsWith('external_layer_')) {
            layerStates[layer.id] = false; // External layers start deactivated
          } else if (layer.id.startsWith('wms_layer_')) {
            // Siempre desactiva las capas WMS al iniciar
            layerStates[layer.id] = false;
          } else {
            layerStates[layer.id] =
                layerStates[layer.id] ?? true; // Other layers default to active
          }
        }
      });
    }
  }

  void handleLayerDelete(String layerId) {
    setState(() {
      if (layerId.startsWith('wms_layer_')) {
        wmsLayers.removeWhere((layer) => layer.id == layerId);
        saveWmsLayers(); // Guardar los cambios de WMS
      } else {
        savedLayers.removeWhere((layer) => layer.id == layerId);
        saveLayers(); // Guardar los cambios de capas de dibujo
      }
      layerStates.remove(layerId);
    });
  }

  void handleLayerFocus(String layerId) {
    SavedDrawingLayer? layer = savedLayers
        .cast<SavedDrawingLayer?>()
        .firstWhere((l) => l?.id == layerId, orElse: () => null);
    if (layer == null) return;

    List<LatLng> allPoints = [];

    for (final poly in layer.polygons) {
      allPoints.addAll(poly.polygon.points);
    }

    for (final line in layer.lines) {
      allPoints.addAll(line.polyline.points);
    }

    for (final marker in layer.points) {
      allPoints.add(marker.marker.point);
    }

    if (allPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(allPoints);
    mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(32)),
    );
  }

  void handleSaveDrawings() {
    if (drawnLines.isEmpty && drawnPolygons.isEmpty && drawnPoints.isEmpty)
      return;

    final newLayer = SavedDrawingLayer(
      id: 'saved_layer_${DateTime.now().millisecondsSinceEpoch}', // Agregado el prefijo saved_layer_
      name: 'Dibujo ${savedLayers.length + 1}',
      lines: List.from(drawnLines),
      polygons: List.from(drawnPolygons),
      points: List.from(drawnPoints),
      timestamp: DateTime.now(),
      rawGeometries: [],
    );

    setState(() {
      savedLayers.add(newLayer);
      layerStates[newLayer.id] = true; // Activar la capa por defecto
      drawnLines.clear();
      drawnPolygons.clear();
      drawnPoints.clear();
    });

    saveLayers();

    // Mostrar mensaje de confirmación
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Capa guardada correctamente'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(top: 20, left: 16, right: 16),
      ),
    );
  }

  void handleEraseLastDrawing() {
    setState(() {
      if (linePoints.isNotEmpty) {
        // Si hay puntos temporales de línea, borra el último
        linePoints.removeLast();
      } else if (polygonPoints.isNotEmpty) {
        // Si hay puntos temporales de polígono, borra el último
        polygonPoints.removeLast();
      } else if (drawnLines.isNotEmpty) {
        // Si hay líneas completas, borra la última
        drawnLines.removeLast();
      } else if (drawnPolygons.isNotEmpty) {
        // Si hay polígonos completos, borra el último
        drawnPolygons.removeLast();
      } else if (drawnPoints.isNotEmpty) {
        // Si hay puntos, borra el último
        drawnPoints.removeLast();
      } else if (drawnCircles.isNotEmpty) {
        // Si hay círculos, borra el último
        drawnCircles.removeLast();
        radiusCenter = null;
        centerMarkers.clear();
      }
    });
  }

  void showDrawingsLayerSelector(
    BuildContext context,
    List<SavedDrawingLayer> savedLayers,
    Function(String, bool) onLayerToggle,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.3),
        pageBuilder: (context, animation, secondaryAnimation) {
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: GestureDetector(
                    onTap: () {},
                    child: DrawingsLayerSelector(
                      savedLayers: savedLayers,
                      onLayerToggle: onLayerToggle,
                      onExport: (layersByFolder, format, fileName) async {
                        final totalLayers = layersByFolder.values
                            .expand((layers) => layers)
                            .length;

                        if (totalLayers == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No hay capas seleccionadas'),
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(
                                top: 20,
                                left: 16,
                                right: 16,
                              ),
                            ),
                          );
                          return;
                        }

                        try {
                          final file = await exportLayersByFolderToKMLorKMZ(
                            layersByFolder,
                            format,
                            fileName,
                          );
                          await Share.shareXFiles([
                            XFile(file.path),
                          ], text: 'Exportación $format');

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Archivo $format exportado correctamente',
                              ),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(
                                top: 20,
                                left: 16,
                                right: 16,
                              ),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al exportar: $e'),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(
                                top: 20,
                                left: 16,
                                right: 16,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void handleDrawingToolSelected(String tool) {
    setState(() {
      switch (tool) {
        case 'point':
          isDrawingPoint = !isDrawingPoint;
          isDrawingLine = false;
          isDrawingPolygon = false;
          isDrawingRadius = false;
          break;
        case 'line':
          if (isDrawingLine) {
            // Finalizar el dibujo actual
            if (linePoints.isNotEmpty) {
              _showLabelInputModal('line');
            }
          }
          isDrawingLine = !isDrawingLine;
          isDrawingPoint = false;
          isDrawingPolygon = false;
          isDrawingRadius = false;
          break;
        case 'polygon':
          // Implement polygon drawing
          if (isDrawingPolygon) {
            // Finalizar el polígono actual
            if (polygonPoints.length >= 3) {
              _showLabelInputModal('polygon');
            }
          }
          isDrawingPolygon = !isDrawingPolygon;
          isDrawingPoint = false;
          isDrawingLine = false;
          isDrawingRadius = false;
          break;
      }
    });
  }

  Future<File> annotateImageWithData(
    File originalImage,
    String label,
    String utm,
    int altitud,
  ) async {
    final imageBytes = await originalImage.readAsBytes();
    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) throw Exception("No se pudo decodificar la imagen");
    await initializeDateFormatting('es_PE', null);
    final now = DateTime.now();
    final fecha = DateFormat('dd MMM yyyy', 'es_PE').format(now);
    final hora = DateFormat('hh:mm a', 'es_PE').format(now).toLowerCase();

    final List<String> lines = [
      "Fecha: $fecha   -   Hora: $hora",
      "UTM WGS 84: $utm",
      "Altitud: $altitud msnm",
      label,
      "Credito: InGeo V1-2025",
    ];

    // Estilos
    const int margin = 16;
    const int lineHeight = 26;
    const int fontSize = 20;
    final img.Color textColor = img.ColorRgb8(255, 255, 255);
    final img.Color bgColor = img.ColorRgba8(0, 0, 0, 128);

    // Tamaño del fondo
    final int rectWidth = 500;
    final int rectHeight = lineHeight * lines.length + 10;
    final int x = original.width - rectWidth - margin;
    final int y = original.height - rectHeight - margin;

    // Fondo negro semitransparente
    img.fillRect(
      original,
      x1: x,
      y1: y,
      x2: x + rectWidth,
      y2: y + rectHeight,
      color: bgColor,
    );

    // Dibujar texto línea por línea
    for (int i = 0; i < lines.length; i++) {
      img.drawString(
        original,
        lines[i],
        font: img.arial14, // fuente más grande
        color: textColor,
        x: x + 10,
        y: y + 5 + i * lineHeight,
      );
    }

    // Guardar imagen anotada
    final tempDir = await getTemporaryDirectory();
    final annotatedFile = File(
      "${tempDir.path}/annotated_${DateTime.now().millisecondsSinceEpoch}.jpg",
    );
    await annotatedFile.writeAsBytes(img.encodeJpg(original));
    return annotatedFile;
  }

  String _createFullDescription(
    String label,
    String locality,
    double lat,
    double lng,
    String utm, {
    String? coords,
    String? observacion,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(label);

    if (coords != null && coords.isNotEmpty) {
      buffer.write('\nCoordenadas: $coords');
    }

    if (locality.isNotEmpty) {
      buffer.write('\nLocalidad: $locality');
    }

    buffer.write('\nLat: ${lat.toStringAsFixed(6)}');
    buffer.write('\nLng: ${lng.toStringAsFixed(6)}');
    buffer.write('\nUTM: $utm');

    if (observacion != null && observacion.isNotEmpty) {
      buffer.write('\nObservación: $observacion');
    }

    return buffer.toString();
  }

  Widget _buildLocationInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _persistPhotos(List<File> photos) async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final List<String> persisted = [];
    for (final file in photos) {
      final String name =
          'ph_${DateTime.now().microsecondsSinceEpoch}${p.extension(file.path)}';
      final String target = p.join(photosDir.path, name);
      await file.copy(target);
      persisted.add(target);
    }
    return persisted;
  }

  void _showLabelInputModal(String drawingType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return LabelInputModal(
          drawingType: drawingType,
          centerPosition: centerPosition,
          availableFolders: folders,
          onFolderCreate: (name) async {
            return _createFolder(name);
          },
          getUTMCoordinates: _getUTMCoordinates,
          annotateImage: annotateImageWithData,
          buildLocationInfoRow: _buildLocationInfoRow,
          onSave: (result) async {
            final utmCoords = _getUTMCoordinates(centerPosition);
            final fullDescription = _createFullDescription(
              result.label,
              result.locality,
              centerPosition.latitude,
              centerPosition.longitude,
              utmCoords,
              coords: result.coords,
              observacion: result.observation,
            );

            List<String> persistedPaths = [];
            List<File> persistedPhotos = [];
            if (result.photos.isNotEmpty) {
              persistedPaths = await _persistPhotos(result.photos);
              persistedPhotos = persistedPaths.map((p) => File(p)).toList();
            }

            if (drawingType == 'line') {
              setState(() {
                drawnLines.add(
                  LabeledPolyline(
                    polyline: Polyline(
                      points: List.from(linePoints),
                      strokeWidth: 3,
                      color: Colors.green,
                    ),
                    label: result.label,
                    locality: result.locality,
                    manualCoordinates: result.coords,
                    observation: result.observation,
                    photos: persistedPaths,
                  ),
                );
                linePoints.clear();
              });
            } else if (drawingType == 'polygon') {
              setState(() {
                drawnPolygons.add(
                  LabeledPolygon(
                    polygon: Polygon(
                      points: List.from(polygonPoints),
                      color: Colors.blue.withOpacity(0.3),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 3,
                      label: result.label,
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      labelPlacement: PolygonLabelPlacement.centroid,
                      rotateLabel: false,
                    ),
                    label: result.label,
                    locality: result.locality,
                    manualCoordinates: result.coords,
                    observation: result.observation,
                    photos: persistedPaths,
                  ),
                );
                polygonPoints.clear();
              });
            } else if (drawingType == 'point') {
              if (drawnPoints.isNotEmpty) {
                final lastPoint = drawnPoints.last.marker.point;
                setState(() {
                  drawnPoints.removeLast();
                });

                setState(() {
                  drawnPoints.add(
                    LabeledMarker(
                      label: result.label,
                      locality: result.locality,
                      manualCoordinates: result.coords,
                      observation: result.observation,
                      photos: persistedPhotos,
                      photoPaths: persistedPaths,
                      marker: Marker(
                        point: lastPoint,
                        width: 100,
                        height: 60,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 0,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                result.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      geometry: GeometryData(
                        name: '',
                        type: 'Point',
                        coordinates: [],
                      ),
                    ),
                  );
                });
              }
            }

            await _saveDrawingWithFolder(
              drawingType,
              result.label,
              result.selectedFolderId,
              result.selectedFolderPath,
              [], // Photos are already persisted and attached to objects
            );

            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dibujo etiquetado'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.only(
                    top: 20,
                    left: 16,
                    right: 16,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  // Modificar la función finishPolygon para mostrar el área
  void finishPolygon() {
    if (polygonPoints.length >= 3) {
      setState(() {
        // Agregar el primer punto al final para cerrar el polígono
        polygonPoints.add(polygonPoints.first);

        // Crear el nuevo polígono
        drawnPolygons.add(
          LabeledPolygon(
            polygon: Polygon(
              points: List.from(polygonPoints),
              color: Colors.red.withOpacity(0.3),
              borderColor: Colors.red,
              borderStrokeWidth: 3,
            ),
            label: '',
          ),
        );
        // Limpiar los puntos y desactivar el modo de dibujo
        polygonPoints.clear();
        isDrawingPolygon = false;
      });
    }
  }

  void _showRadiusInput() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Ingrese el radio'),
          content: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Radio en kilómetros',
              suffixText: 'km',
            ),
            onChanged: (value) {
              radiusInKm = double.tryParse(value) ?? 1.0;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _drawCircle();
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  void _drawCircle() {
    if (radiusCenter != null && mapController != null) {
      final metersPerPixel = _calculateMetersPerPixel();
      final radiusInPixels = (radiusInKm * 1000) / metersPerPixel;

      setState(() {
        // Limpiamos los círculos anteriores

        drawnCircles.add(
          Marker(
            point: radiusCenter!,
            width: radiusInPixels * 2, // Diámetro en píxeles
            height: radiusInPixels * 2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.3),
                border: Border.all(color: Colors.red, width: 2),
              ),
            ),
          ),
        );
        // isDrawingRadius = false;
        // radiusCenter = null;
      });
    }
  }

  double _calculateMetersPerPixel() {
    final zoom = mapController.zoom;
    return 156543.03392 *
        math.cos((radiusCenter ?? centerPosition).latitude * math.pi / 180) /
        math.pow(2, zoom);
  }

  int _currentScaleDenominator() {
    double zoomGuess = 14.0;
    try {
      final z = mapController.zoom;
      if (z.isFinite) zoomGuess = z;
    } catch (_) {}
    final lat = centerPosition.latitude;
    final mpp =
        156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoomGuess);
    const dpi = 96.0;
    const inchesPerMeter = 39.37007874015748;
    final scale = mpp * dpi * inchesPerMeter;
    if (!scale.isFinite) return 0;
    return scale.round();
  }

  void _setZoomFromScale(int scaleDenominator) {
    if (scaleDenominator <= 0) return;

    final lat = centerPosition.latitude;
    const dpi = 96.0;
    const inchesPerMeter = 39.37007874015748;
    const earthCircumferencePerTile = 156543.03392;

    final c =
        earthCircumferencePerTile *
        math.cos(lat * math.pi / 180) *
        dpi *
        inchesPerMeter;
    final twoToZoom = c / scaleDenominator;
    final newZoom = math.log(twoToZoom) / math.log(2);

    if (newZoom.isFinite) {
      mapController.move(centerPosition, newZoom);
    }
  }

  String _formatThousandsInt(int n) {
    final formatter = NumberFormat.decimalPattern();
    return formatter.format(n);
  }

  void _showGeometryInfo(BuildContext context, GeometryData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.4,
          maxChildSize: 0.7,
          minChildSize: 0.2,
          builder: (_, controller) => Container(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: controller,
              children: [
                Text(
                  data.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text("Tipo: ${data.type}"),
                if (data.styleUrl != null) Text("Estilo: ${data.styleUrl}"),
                const SizedBox(height: 8),
                const Text("Coordenadas:"),
                ...data.coordinates.map(
                  (c) => Text(
                    "• ${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        actions: [
          SizedBox(
            width: 100,
            child: ElevatedButton(
              onPressed: () {
                // Implementar compartir app
                Share.share('¡Descarga nuestra app!');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.withOpacity(0.7),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text(
                'Compartir App',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              showMenu(
                context: context,
                position: const RelativeRect.fromLTRB(100, 100, 0, 0),
                items: [
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.description),
                        SizedBox(width: 8),
                        Text('Generar Reporte'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart),
                        SizedBox(width: 8),
                        Text('Generar Excel'),
                      ],
                    ),
                  ),
                ],
              ).then((value) async {
                if (value == 'report') {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    final reportFile = await PdfReportGenerator.generateReport(
                      savedLayers,
                    );
                    Navigator.pop(context);
                    await Share.shareXFiles([
                      XFile(reportFile.path),
                    ], subject: 'Reporte de Capas');
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al generar el reporte: $e'),
                      ),
                    );
                  }
                } else if (value == 'excel') {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    final excelFile =
                        await PdfReportGenerator.generateExcelReport(
                          savedLayers,
                        );
                    Navigator.pop(context);
                    await Share.shareXFiles([
                      XFile(excelFile.path),
                    ], subject: 'Reporte Excel');
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al generar el Excel: $e')),
                    );
                  }
                }
              });
            },
            icon: const Icon(Icons.more_vert, color: Colors.black87),
          ),
          const SizedBox(width: 8),
        ],
      ),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          FlutterMap(
            key: mapKey,
            mapController: mapController,
            options: MapOptions(
              center: centerPosition,
              zoom: 6.0,
              onTap: _handleTap,
              onMapEvent: (event) {
                if (event.source == MapEventSource.dragEnd ||
                    event.source == MapEventSource.onDrag ||
                    event.source == MapEventSource.multiFingerEnd ||
                    event.source == MapEventSource.scrollWheel ||
                    event.source == MapEventSource.mapController) {
                  _onMapMoved();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: mapUrlTemplate,
                userAgentPackageName: 'com.ingeo.app',
              ),
              // Add WMS layers here
              ...getWmsTileLayers(),
              ..._buildWmsLayers(),
              if (measurePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: measurePoints,
                      strokeWidth: 3,
                      color: Colors.blue,
                    ),
                  ],
                ),
              if (measurePoints.isNotEmpty)
                MarkerLayer(
                  markers: measurePoints
                      .map(
                        (point) => Marker(
                          point: point,
                          width: 5,
                          height: 5,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),

              // Agregar marcadores KML
              if (kmlMarkers.isNotEmpty) MarkerLayer(markers: kmlMarkers),
              // Agregar polilíneas KML
              if (kmlPolylines.isNotEmpty)
                PolylineLayer(polylines: kmlPolylines),
              if (kmlPolygons.isNotEmpty) PolygonLayer(polygons: kmlPolygons),
              // ...Otras capas existentes ...
              // Renderizar cada capa guardada si está activa
              ...savedLayers
                  .where((layer) => layerStates[layer.id] == true)
                  .map((layer) {
                    return [
                      if (layer.lines.isNotEmpty) ...[
                        // Usar spread operator para agregar múltiples widgets
                        PolylineLayer(
                          polylines: layer.lines
                              .map((labeledLine) => labeledLine.polyline)
                              .toList(),
                        ),
                        MarkerLayer(
                          markers: layer.lines.map((line) {
                            // Calcular el punto medio de la línea
                            final points = line.polyline.points;
                            final middleIndex = points.length ~/ 2;
                            final middlePoint = points[middleIndex];
                            return Marker(
                              point: middlePoint,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                  vertical: 0,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  line.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (layer.polygons.isNotEmpty)
                        PolygonLayer(
                          polygons: layer.polygons.map((p) {
                            return Polygon(
                              points: p.polygon.points,
                              color: p.polygon.color,
                              borderColor: p.polygon.borderColor,
                              borderStrokeWidth: p.polygon.borderStrokeWidth,
                              isFilled: p.polygon.isFilled,
                              label: p.label.split('\n').first,
                              labelStyle: p.polygon.labelStyle,
                              labelPlacement: p.polygon.labelPlacement,
                              rotateLabel: p.polygon.rotateLabel,
                            );
                          }).toList(),
                        ),
                      if (layer.points.isNotEmpty)
                        MarkerLayer(
                          markers: layer.points.map((lm) => lm.marker).toList(),
                        ),
                    ];
                  })
                  .expand((widgets) => widgets),
              // Drawing tools
              if (drawnPoints.isNotEmpty)
                MarkerLayer(
                  markers: drawnPoints
                      .map((labeledMarker) => labeledMarker.marker)
                      .toList(),
                ),
              if (linePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: linePoints,
                      strokeWidth: 3,
                      color: Colors.red,
                    ),
                  ],
                ),
              if (drawnLines.isNotEmpty) ...[
                // Usar spread operator para agregar múltiples widgets
                PolylineLayer(
                  polylines: drawnLines.map((line) => line.polyline).toList(),
                ),
                MarkerLayer(
                  markers: drawnLines.map((line) {
                    // Calcular el punto medio de la línea
                    final points = line.polyline.points;
                    final middleIndex = points.length ~/ 2;
                    final middlePoint = points[middleIndex];
                    return Marker(
                      point: middlePoint,
                      width: 100,
                      height: 30,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 1,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          line.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (polygonPoints.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: polygonPoints,
                      color: Colors.red.withOpacity(0.3),
                      borderColor: Colors.red,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (drawnPolygons.isNotEmpty)
                PolygonLayer(
                  polygons: drawnPolygons.map((p) {
                    return Polygon(
                      points: p.polygon.points,
                      color: p.polygon.color,
                      borderColor: p.polygon.borderColor,
                      borderStrokeWidth: p.polygon.borderStrokeWidth,
                      isFilled: p.polygon.isFilled,
                      label: p.label.split('\n').first,
                      labelStyle: p.polygon.labelStyle,
                      labelPlacement: p.polygon.labelPlacement,
                      rotateLabel: p.polygon.rotateLabel,
                    );
                  }).toList(),
                ),

              if (centerMarkers.isNotEmpty) MarkerLayer(markers: centerMarkers),
              if (drawnCircles.isNotEmpty) MarkerLayer(markers: drawnCircles),

              // Tracking
              if (currentTrackingPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentTrackingPosition!,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isTracking
                              ? Image.asset(
                                  'assets/icon/car_position.png',
                                  width: 20,
                                  height: 20,
                                  color: Colors
                                      .yellow, // Aplica color si es necesario
                                )
                              : const Icon(
                                  Icons.my_location,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),

              if (isTracking && trackPoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints,
                      color: Colors.blueAccent,
                      strokeWidth: 3.0,
                    ),
                  ],
                ),
              // Locator
              if (showLocationMarker)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentPosition,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (isMeasuringDistance)
            Positioned(
              bottom: 225,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Puntos marcados: ${measurePoints.length}'),
                    if (measurePoints.isNotEmpty)
                      Text(
                        'Distancia total: ${_calculateDistance().toStringAsFixed(2)} m.',
                      ),
                  ],
                ),
              ),
            ),
          if (isDrawingPolygon)
            Positioned(
              bottom: 225,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Puntos marcados: ${polygonPoints.length}'),
                    if (polygonPoints.length >= 3) ...[
                      Text(
                        'm²: ${calculatePolygonArea(polygonPoints).toStringAsFixed(2)}',
                      ),
                      Text(
                        'km²: ${(calculatePolygonArea(polygonPoints) / 1000000).toStringAsFixed(2)}',
                      ),
                      Text(
                        'ha: ${(calculatePolygonArea(polygonPoints) / 10000).toStringAsFixed(2)}',
                      ),
                      Text(
                        'Perímetro: ${calculatePolygonPerimeter(polygonPoints).toStringAsFixed(2)} m',
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Coordenadas en la parte superior
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(
                    0.7,
                  ), // Fondo semi-transparente
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lat Lon
                    Row(
                      children: [
                        const SizedBox(
                          width: 120,
                          child: Text(
                            'Lat Lon:',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${centerPosition.latitude.toStringAsFixed(9)} ${centerPosition.longitude.toStringAsFixed(9)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // UTM
                    Row(
                      children: [
                        const SizedBox(
                          width: 120,
                          child: Text(
                            'UTM:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _getUTMCoordinates(centerPosition),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Margen de error
                    Row(
                      children: [
                        const SizedBox(
                          width: 120,
                          child: Text(
                            'Precisión GPS:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '±${currentAccuracy?.toStringAsFixed(2)} m  ·  Altitud: ${currentElevation != null ? '${currentElevation} msnm' : '...'}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(
                          width: 120,
                          child: Text(
                            'Escala:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Arial',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ScaleSelector(
                            currentScale: _currentScaleDenominator(),
                            onScaleSelected: _setZoomFromScale,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Línea vertical
          Center(
            child: Container(
              width: 1,
              height: double.infinity,
              color: Colors.red.withOpacity(0.5),
            ),
          ),
          // Línea horizontal
          Center(
            child: Container(
              width: double.infinity,
              height: 1,
              color: Colors.red.withOpacity(0.5),
            ),
          ),

          Positioned(
            left: 10,
            top: 175, // Posición inicial del contenedor principal
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isExpanded ? 100 : 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Botón para expandir/contraer (siempre visible)
                  Container(
                    width: 100,
                    color: Colors.white.withOpacity(
                      0.7,
                    ), // Fondo semitransparente o sólido
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(
                          _isExpanded
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                          color: Colors.black,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _isExpanded = !_isExpanded),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                  ),

                  // Botones (solo visibles cuando está expandido)
                  if (_isExpanded) ...[
                    MenuButton(
                      text: 'Importar',
                      onPressed: toggleFileSelector,
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 4),
                    MenuButton(
                      text: 'Exportar',
                      onPressed: () => showDrawingsLayerSelector(
                        context,
                        savedLayers,
                        (id, selected) {},
                      ),
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 4),
                    MenuButton(
                      text: 'Mapa Base',
                      onPressed: toggleMapSelector,
                      color: const Color(0xFF98AFBA),
                    ),
                    const SizedBox(height: 4),
                    MenuButton(
                      text: 'Capas\nTemáticas',
                      onPressed: toggleToolsSelector,
                      color: Colors.teal,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showMapSelector)
            Positioned(
              left: 125,
              top: 218, // Alineado con el primer botón
              child: BaseMapSelector(
                currentMapType: currentMapType,
                onMapTypeChanged: changeMapType,
              ),
            ),

          Positioned(
            right: 10,
            top: 175,
            child: Column(
              children: [
                Container(
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
                    onPressed: orientToNorth,
                    icon: const Icon(Icons.navigation),
                    color: Colors.teal,
                    iconSize: 28,
                    tooltip: 'Orientar al norte',
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            top: 235,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StyledMapIconButton(
                  icon: Icons.add,
                  tooltip: 'Acercar',
                  onPressed: () {
                    final zoom = mapController.zoom + 1;
                    mapController.move(mapController.center, zoom);
                    setState(() {
                      if (isDrawingRadius && radiusCenter != null) {
                        drawnCircles.clear();
                        _drawCircle();
                      }
                    });
                    _saveMapConfig();
                  },
                ),
                const SizedBox(height: 10),
                StyledMapIconButton(
                  icon: Icons.remove,
                  tooltip: 'Alejar',
                  onPressed: () {
                    final zoom = mapController.zoom - 1;
                    mapController.move(mapController.center, zoom);
                    setState(() {
                      if (isDrawingRadius && radiusCenter != null) {
                        drawnCircles.clear();
                        _drawCircle();
                      }
                    });
                    _saveMapConfig();
                  },
                ),
              ],
            ),
          ),

          Positioned(
            right: 10,
            bottom: 300,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isMenuVisible = !isMenuVisible;
                });
              },
              child: Container(
                width: 55,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isMenuVisible
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  color: Colors.black87,
                  size: 24,
                ),
              ),
            ),
          ),
          if (isMenuVisible) ...[
            Positioned(
              right: 10,
              bottom: 240,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: 'toggle_currentLocation',
                    onPressed: _getCurrentLocation,
                    backgroundColor: isLoadingLocation
                        ? const Color(0xFF9F0712)
                        : Colors.teal.withOpacity(0.7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isLoadingLocation
                              ? Icons.close
                              : Icons.my_location_sharp,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'GPS',
                          style: TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              bottom: 170,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AccessControlService().isAuthenticated,
                    builder: (context, isAuth, child) {
                      final hasAccess = AccessControlService()
                          .canAccess(AppFeature.trackRecording);
                      final isLocked = !hasAccess;

                      return FloatingActionButton(
                        heroTag: 'toggle_track',
                        onPressed: () {
                          if (isLocked) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LoginScreen(
                                  onLoginSuccess: () => toggleTracking(),
                                ),
                              ),
                            );
                            return;
                          }
                          toggleTracking();
                        },
                        backgroundColor: isLocked
                            ? Colors.grey.withOpacity(0.7)
                            : (isTracking
                                ? const Color(0xFF9F0712)
                                : Colors.teal.withOpacity(0.7)),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                isTracking
                                    ? const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      )
                                    : Image.asset(
                                        'assets/icon/track_icon.png',
                                        width: 25,
                                        height: 20,
                                        color: Colors.white,
                                      ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Track',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.white),
                                ),
                              ],
                            ),
                            if (isLocked)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.lock,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              bottom: 100,
              child: DrawingTools(
                onDrawingToolSelected: handleDrawingToolSelected,
                onSaveDrawings: handleSaveDrawings,
                onEraseLastDrawing: handleEraseLastDrawing,
              ),
            ),
          ],
          Positioned(
            left: 0,
            top: 120,
            right: 0, // opcional, para que se ajuste al ancho de la pantalla
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: CustomSearchBar(onLocationSelected: _onLocationSelected),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 100,
            child: MeasurementTools(
              onMeasurementToolSelected: handleMeasurementToolSelected,
            ),
          ),
          // Botones en la parte inferior
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        final String coordText =
                            'Lat Lon:     ${centerPosition.latitude.toStringAsFixed(9)} ${centerPosition.longitude.toStringAsFixed(9)}\n'
                            'UTM:         ${_getUTMCoordinates(centerPosition)}\n'
                            'Google Maps: https://www.google.com/maps/search/?api=1&query=${centerPosition.latitude},${centerPosition.longitude}';

                        Clipboard.setData(ClipboardData(text: coordText)).then((
                          _,
                        ) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Coordenadas copiadas al portapapeles',
                              ),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(
                                top: 20,
                                left: 16,
                                right: 16,
                              ),
                            ),
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.withOpacity(0.7),
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Copiar X,Y',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (isLoadingLocation) return; // Evitar múltiples clics

                        await _getCurrentLocation(); // Esperar a que termine

                        if (currentPosition != null) {
                          // Verificar que se obtuvo la ubicación
                          final String message =
                              '📍 Mi ubicación actual:\n'
                              'https://www.google.com/maps/search/?api=1&query=${currentPosition.latitude},${currentPosition.longitude}';
                          Share.share(message);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.withOpacity(0.7),
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Compartir Ubicación',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showToolsSelector)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                // Envolver en Material para asegurar que esté por encima
                elevation: 8, // Añadir elevación para enfatizar que está encima
                child: WmsLayerSelector(
                  layerStates: layerStates,
                  onLayerToggle: toggleLayer,
                  onClose: toggleWmsLayerSelector,
                  savedLayers: savedLayers,
                  onLayerDelete: handleLayerDelete,
                  onLayerFocus: handleLayerFocus,
                  mapController: mapController,
                  onWmsLayerAdd: _handleAddWmsLayer,
                  wmsLayers: wmsLayers,
                  customLayerGroups: layerGroups,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void copyCoordinates(LatLng position) {
    String coordinates =
        '${position.latitude.toStringAsFixed(9)} ${position.longitude.toStringAsFixed(9)}';
    Clipboard.setData(ClipboardData(text: coordinates)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordenadas copiadas al portapapeles'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(top: 20, left: 16, right: 16),
        ),
      );
    });
  }

  // Métodos para manejo de carpetas
  Future<void> _saveFolders(List<Folder> foldersList) async {
    final prefs = await SharedPreferences.getInstance();
    final foldersJson = foldersList.map((folder) => folder.toJson()).toList();
    await prefs.setString('folders', jsonEncode(foldersJson));
    setState(() {
      folders = foldersList;
    });
  }

  // Cargar carpetas
  Future<void> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final foldersString = prefs.getString('folders');
    if (foldersString != null) {
      final foldersJson = jsonDecode(foldersString) as List;
      setState(() {
        folders = foldersJson.map((json) => Folder.fromJson(json)).toList();
      });
    }
  }

  Future<Folder> _createFolder(String name) async {
    final newFolder = Folder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
    );
    
    final updatedFolders = List<Folder>.from(folders)..add(newFolder);
    await _saveFolders(updatedFolders);
    
    return newFolder;
  }

  // Ya no necesitamos estas funciones para rutas jerárquicas
  String _getFolderPathName(String folderId) {
    final folder = folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => Folder(id: '', name: '', createdAt: DateTime.now()),
    );
    return folder.name;
  }

  String _getFolderPath(String folderId) {
    final folder = folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => Folder(id: '', name: '', createdAt: DateTime.now()),
    );
    return folder.name;
  }

  Future<void> _saveDrawingWithFolder(
    String drawingType,
    String label,
    String? folderId,
    String? folderPath,
    List<File> photos,
  ) async {
    List<String> persistedPaths = [];
    if (photos.isNotEmpty) {
      persistedPaths = await _persistPhotos(photos);
    }
    final Map<String, dynamic>? attributes = persistedPaths.isNotEmpty
        ? {
            if (drawingType == 'line') 'photos_line': persistedPaths,
            if (drawingType == 'polygon') 'photos_polygon': persistedPaths,
            if (drawingType == 'point') 'photos_point': persistedPaths,
          }
        : null;

    final newLayer = SavedDrawingLayer(
      id: 'saved_layer_${DateTime.now().millisecondsSinceEpoch}',
      name: label.split('\n').first,
      lines: drawingType == 'line' ? List.from(drawnLines) : [],
      polygons: drawingType == 'polygon' ? List.from(drawnPolygons) : [],
      points: drawingType == 'point' ? List.from(drawnPoints) : [],
      timestamp: DateTime.now(),
      rawGeometries: [],
      folderId: folderId,
      folderPath: folderPath,
      attributes: attributes,
    );

    setState(() {
      savedLayers.add(newLayer);
      layerStates[newLayer.id] = true;
      if (drawingType == 'line') {
        drawnLines.clear();
      } else if (drawingType == 'polygon') {
        drawnPolygons.clear();
      } else if (drawingType == 'point') {
        drawnPoints.clear();
      }
    });

    await saveLayers();
  }

  // Propiedades para KML y carpetas
  List<Marker> kmlMarkers = [];
  List<Polyline> kmlPolylines = [];
  List<Polygon> kmlPolygons = [];

  void importFile() async {
    final importedLayer = await ImportLayersUtil.importKmlOrKmz();

    if (importedLayer == null) return;

    setState(() {
      savedLayers.add(importedLayer);
      layerStates[importedLayer.id] = true;
    });
    saveLayers();

    // Mostrar diálogo de confirmación con opción de ver atributos
    if (mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Archivo Importado'),
            content: Text(
              'Se ha importado exitosamente: ${importedLayer.name}',
            ),
            actions: [
              if (importedLayer.attributes != null)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ImportLayersUtil.showFileAttributes(
                      context,
                      importedLayer.attributes!,
                    );
                  },
                  child: const Text('Ver Atributos'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    }

    // Centrar el mapa
    if (importedLayer.points.isNotEmpty) {
      mapController.move(importedLayer.points.first.marker.point, 12.0);
    } else if (importedLayer.lines.isNotEmpty &&
        importedLayer.lines.first.polyline.points.isNotEmpty) {
      mapController.move(importedLayer.lines.first.polyline.points.first, 12.0);
    } else if (importedLayer.polygons.isNotEmpty &&
        importedLayer.polygons.first.polygon.points.isNotEmpty) {
      mapController.move(importedLayer.polygons.first.polygon.points.first, 12.0);
    }
  }
}
