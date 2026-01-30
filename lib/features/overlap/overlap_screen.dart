import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ingeo_app/models/layer_states.dart';
import 'package:ingeo_app/models/saved_drawing_layer.dart';
import 'package:ingeo_app/features/geolocation/components/base_map_selector.dart';
import 'package:ingeo_app/features/geolocation/components/search_bar.dart';
import 'package:ingeo_app/features/geolocation/components/wms_layer_selector.dart';
import 'package:ingeo_app/features/geolocation/components/wms_feature_info.dart';
import 'package:ingeo_app/features/overlap/components/active_layers_panel.dart';
import 'package:ingeo_app/utils/import_layers.dart';
import 'package:ingeo_app/widgets/buttons/menu_button.dart';
import 'package:ingeo_app/widgets/buttons/styled_map_icon_button.dart';
import 'package:ingeo_app/widgets/common/scale_selector.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utm/utm.dart';
import 'package:ingeo_app/core/services/elevation_service.dart';
import 'package:ingeo_app/data/layers/layer_repository.dart';
import 'dart:math' as math;

class OverlapScreen extends StatefulWidget {
  const OverlapScreen({super.key});

  @override
  State<OverlapScreen> createState() => _OverlapScreenState();
}

class _OverlapScreenState extends State<OverlapScreen> {
  final mapController = MapController();
  bool _isExpanded = false;
  final GlobalKey mapKey = GlobalKey();

  String currentMapType = 'osm';
  bool showMapSelector = false;
  bool showToolsSelector = false;
  bool showFileSelector = false;

  LatLng centerPosition = const LatLng(-9.7786, -74.9463);
  bool showLayerSelector = false;
  bool showActiveLayers = false;

  bool isLoadingLocation = false;
  bool showLocationMarker = false;
  LatLng currentPosition = const LatLng(-12.0464, -77.0428);
  StreamSubscription<Position>? _positionStreamSubscription;

  List<SavedDrawingLayer> savedLayers = [];

  // Variables para herramientas de dibujo
  bool isDrawingPoint = false;

  List<LabeledPolyline> drawnLines = [];
  bool isDrawingLine = false;
  List<LatLng> linePoints = [];
  bool isDrawingPolygon = false;
  List<LatLng> polygonPoints = [];
  List<Polygon> drawnPolygons = [];

  double? currentAccuracy = 0;
  int? currentElevation;

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

  final Map<String, bool> layerStates = {
    'sp_grilla_utm_peru': false,
    'sp_anp_nacionales_definidas': false,
    'sp_areas_conservacion_privada': false,
    'sp_areas_conservacion_regional': false,
    'sp_puntos_geodesicos': false,
    'sp_zonas_amortiguamiento': false,
    'sp_zonas_reservadas': false,
    'sp_cartografia_peligros': false,
  };

  final List<LayerGroup> layerGroups = LayerRepository.overlapLayers;

  @override
  void initState() {
    super.initState();
    _getCurrentAccuracy();
    _updateElevation();
    loadLayers();
    _loadMapConfig();
  }

  Future<void> _getCurrentLocation() async {
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
        final locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
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
        setState(() {
          isLoadingLocation = false;
          showLocationMarker = false;
        });
      }
    }
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
        for (var layer in savedLayers) {
          layerStates[layer.id] = layerStates[layer.id] ?? true;
        }
      });
    }
  }

  String _getUTMCoordinates(LatLng position) {
    final utmResult = UTM.fromLatLon(
      lat: position.latitude,
      lon: position.longitude,
    );
    return '${utmResult.easting.round()}E  ${utmResult.northing.round()}N  ${utmResult.zoneNumber}${utmResult.zoneLetter}';
  }

  void _onLocationSelected(LatLng location) {
    mapController.move(location, 15.0);
    _saveMapConfig();
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

  void toggleMapSelector() {
    setState(() {
      showMapSelector = !showMapSelector;
      if (showMapSelector) {
        showToolsSelector = false;
        showFileSelector = false;
      }
    });
  }

  void changeMapType(String type) {
    setState(() {
      currentMapType = type;
      showMapSelector = false;
    });
    _saveMapConfig();
  }

  void _onMapMoved() {
    setState(() {
      centerPosition = mapController.center;
    });
    _updateElevation();
    _saveMapConfig();
  }

  Future<void> _loadMapConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedType = prefs.getString('overlap_map_type');
    final lat = prefs.getDouble('overlap_map_center_lat');
    final lng = prefs.getDouble('overlap_map_center_lng');
    final zoom = prefs.getDouble('overlap_map_zoom');
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
      mapController.move(pos, zoom);
      await _updateElevation();
    }
  }

  Future<void> _saveMapConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlap_map_type', currentMapType);
    final center = mapController.center;
    await prefs.setDouble('overlap_map_center_lat', center.latitude);
    await prefs.setDouble('overlap_map_center_lng', center.longitude);
    await prefs.setDouble('overlap_map_zoom', mapController.zoom);
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

  void _handleTap(TapPosition tapPosition, LatLng point) {
    final RenderBox box =
        mapKey.currentContext?.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(tapPosition.global);
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

  void toggleActiveLayers() {
    setState(() {
      showActiveLayers = !showActiveLayers;
    });
  }

  void toggleLayerSelector() {
    setState(() {
      showLayerSelector = !showLayerSelector;
    });
  }

  void handleLayerToggle(String layerId, bool value) {
    setState(() {
      layerStates[layerId] = value;
    });
  }

  void handleLayerDelete(String layerId) {
    setState(() {
      layerStates.remove(layerId);
      savedLayers.removeWhere((layer) => layer.id == layerId);
    });
    saveLayers();
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

  void toggleFileSelector() {
    setState(() {
      importFile();

      showMapSelector = false;
    });
  }

  void importFile() async {
    final importedLayer = await ImportLayersUtil.importKmlOrKmz();

    if (importedLayer == null) return;

    setState(() {
      savedLayers.add(importedLayer);
      layerStates[importedLayer.id] = true;
    });
    saveLayers();

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

  void _handleIntersectionResult(SavedDrawingLayer layer) {
    setState(() {
      savedLayers.add(layer);
      layerStates[layer.id] = true;
      // Abrir el selector de capas para ver el resultado
      showLayerSelector = true;
      showActiveLayers = false; // Cerrar el panel de análisis
    });
    saveLayers();

    // Enfocar la nueva capa
    handleLayerFocus(layer.id);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capa de intersección agregada al mapa')),
    );
  }

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

  void orientToNorth() {
    mapController.rotate(0.0);
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
      _saveMapConfig();
    }
  }

  String _formatThousandsInt(int n) {
    final formatter = NumberFormat.decimalPattern();
    return formatter.format(n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis de Superposición'),
        centerTitle: true,
        elevation: 2,
      ),
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
                    event.source == MapEventSource.scrollWheel) {
                  _onMapMoved();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: mapUrlTemplate,
                userAgentPackageName: 'com.ingeo.app',
                // Añadir atribución adecuada
                // attribution: 'Map data © OpenStreetMap contributors',
                // Añadir parámetros adicionales para evitar bloqueos
                additionalOptions: const {'useCache': 'true'},
                // Añadir subdominio para distribuir las peticiones
                subdomains: const ['a', 'b', 'c'],
                // Añadir tiempo de caché
                tileProvider: NetworkTileProvider(),
              ),
              ...getWmsTileLayers(),
              ...savedLayers
                  .where((layer) => layerStates[layer.id] == true)
                  .map((layer) {
                    return [
                      if (layer.points.isNotEmpty)
                        MarkerLayer(
                          markers: layer.points.map((p) => p.marker).toList(),
                        ),
                      if (layer.lines.isNotEmpty)
                        PolylineLayer(
                          polylines: layer.lines
                              .map((line) => line.polyline)
                              .toList(),
                        ),
                      if (layer.polygons.isNotEmpty)
                        PolygonLayer(
                          polygons:
                              layer.polygons.map((p) => p.polygon).toList(),
                        ),
                    ];
                  })
                  .expand((layers) => layers),
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
                  color: Colors.white.withOpacity(0.7),
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
                            '${_getUTMCoordinates(centerPosition)}',
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
                            'Margen de error:',
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
                // ... existing code ...
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 120,
            right: 0,
            child: Center(
              child: CustomSearchBar(onLocationSelected: _onLocationSelected),
            ),
          ),
          Positioned(
            left: 10,
            top: 175,
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
                  Container(
                    width: 110,
                    color: Colors.white.withOpacity(0.7),
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
                  if (_isExpanded) ...[
                    MenuButton(
                      text: 'Mapa Base',
                      onPressed: toggleMapSelector,
                      color: const Color(0xFF98AFBA),
                    ),
                    const SizedBox(height: 2),
                    MenuButton(
                      text: 'Importar',
                      onPressed: toggleFileSelector,
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 6),
                    MenuButton(
                      text: 'Capas\nTemáticas',
                      onPressed: toggleLayerSelector,
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 6),
                    MenuButton(
                      text: 'Analisis\nSuperposición',
                      onPressed: toggleActiveLayers,
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
              top: 140, // Alineado con el primer botón
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
                    _saveMapConfig();
                  },
                ),
              ],
            ),
          ),
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
          if (showActiveLayers)
            ActiveLayersPanel(
              isVisible: true,
              layerStates: layerStates,
              layerGroups: layerGroups,
              savedLayers: savedLayers,
              onLayerToggle: handleLayerToggle,
              onClose: toggleActiveLayers,
              onIntersectionResult: _handleIntersectionResult,
            ),
          if (showLayerSelector)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: WmsLayerSelector(
                layerStates: layerStates,
                onLayerToggle: handleLayerToggle,
                onClose: toggleLayerSelector,
                savedLayers: savedLayers,
                onLayerDelete: handleLayerDelete,
                onLayerFocus: handleLayerFocus,
                mapController: mapController,
                customLayerGroups: layerGroups,
              ),
            ),
        ],
      ),
    );
  }
}
