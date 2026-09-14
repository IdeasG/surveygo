import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';
import 'package:surveygo/core/utils/mbtiles_service.dart';

enum MapBaseLayer {
  streets,
  satellite,
  terrain,
  mbtiles,
}

class MapInputPage extends StatefulWidget {
  final String? initialValue;
  final String questionText;
  final GeoGeometryType defaultGeometryType;
  final bool allowGpsOnly;

  const MapInputPage({
    Key? key,
    this.initialValue,
    required this.questionText,
    this.defaultGeometryType = GeoGeometryType.point,
    this.allowGpsOnly = false,
  }) : super(key: key);

  @override
  State<MapInputPage> createState() => _MapInputPageState();
}

class _MapInputPageState extends State<MapInputPage> {
  final MapController _mapController = MapController();
  late GeoGeometryType _geometryType;
  final List<LatLng> _points = [];
  LatLng _mapCenter = const LatLng(-12.06, -77.0375); // Lima default
  LatLng? _currentGpsLocation;
  double? _gpsAccuracy;
  bool _isLoadingLocation = false;
  MapBaseLayer _selectedBaseLayer = MapBaseLayer.streets;

  // Capacidades Tácticas y Ergonomía de Campo
  bool _useCrosshairMode = true; // Retícula central activa por defecto
  final ValueNotifier<LatLng> _reticleCenterNotifier =
      ValueNotifier<LatLng>(const LatLng(-12.06, -77.0375));

  // Modo Caminado de Lindero Continuo (Stream GPS)
  bool _isStreaming = false;
  StreamSubscription<Position>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _geometryType = widget.defaultGeometryType;

    _loadInitialGeometry();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _stopStreamTracking();
    _reticleCenterNotifier.dispose();
    super.dispose();
  }

  void _loadInitialGeometry() {
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      final parsed = GisCalculator.fromGeoJsonOrString(widget.initialValue);
      if (parsed != null) {
        _geometryType = parsed.type;
        _points.addAll(parsed.points);
        if (_points.isNotEmpty) {
          _mapCenter = _points.first;
          _reticleCenterNotifier.value = _points.first;
        }
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        final userLatLng = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _currentGpsLocation = userLatLng;
            _gpsAccuracy = pos.accuracy;
            if (_points.isEmpty) {
              _mapCenter = userLatLng;
              _reticleCenterNotifier.value = userLatLng;
              _mapController.move(userLatLng, 16.5);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error obteniendo ubicación GPS: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng latLng) {
    if (_useCrosshairMode) {
      // En modo retícula se prefiere el botón táctil de pulgar para evitar falsos toques
      return;
    }

    if (widget.allowGpsOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta pregunta requiere captura satelital real. Use el botón "Mi GPS".'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      if (_geometryType == GeoGeometryType.point) {
        _points.clear();
        _points.add(latLng);
      } else {
        _points.add(latLng);
      }
    });
  }

  /// Fija un vértice exactamente en las coordenadas de la retícula central
  void _addPointFromReticle() {
    if (widget.allowGpsOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta pregunta requiere captura satelital real. Use "Mi GPS".'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final target = _mapController.camera.center;

    setState(() {
      if (_geometryType == GeoGeometryType.point) {
        _points.clear();
        _points.add(target);
      } else {
        _points.add(target);
      }
    });
  }

  /// Añade la ubicación GPS simple actual
  void _addCurrentLocationPoint() {
    if (_currentGpsLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obteniendo señal GPS del satélite... por favor espera')),
      );
      _fetchCurrentLocation();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      if (_geometryType == GeoGeometryType.point) {
        _points.clear();
        _points.add(_currentGpsLocation!);
      } else {
        _points.add(_currentGpsLocation!);
      }
      _mapController.move(_currentGpsLocation!, 17.0);
    });
  }

  /// Promediado de GPS Antiruido: Toma 10 muestras consecutivas para eliminar rebotes
  Future<void> _startGpsAveraging() async {
    HapticFeedback.selectionClick();
    int samplesCount = 0;
    const int targetSamples = 10;
    final List<Position> samples = [];
    bool isCanceled = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            if (samples.isEmpty && !isCanceled) {
              Future.microtask(() async {
                for (int i = 0; i < targetSamples; i++) {
                  if (isCanceled || !mounted) break;
                  try {
                    final pos = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.best,
                        timeLimit: Duration(seconds: 4),
                      ),
                    );
                    samples.add(pos);
                    samplesCount++;
                    if (mounted) {
                      setDialogState(() {});
                    }
                  } catch (e) {
                    debugPrint('Error en muestra GPS: $e');
                  }
                  await Future.delayed(const Duration(milliseconds: 350));
                }

                if (samples.isNotEmpty && !isCanceled && mounted) {
                  double sumLat = 0;
                  double sumLng = 0;
                  double sumAcc = 0;
                  for (var s in samples) {
                    sumLat += s.latitude;
                    sumLng += s.longitude;
                    sumAcc += s.accuracy;
                  }
                  final avgLat = sumLat / samples.length;
                  final avgLng = sumLng / samples.length;
                  final avgAcc = sumAcc / samples.length;
                  final avgPoint = LatLng(avgLat, avgLng);

                  Navigator.of(ctx).pop();

                  HapticFeedback.heavyImpact();
                  setState(() {
                    _currentGpsLocation = avgPoint;
                    _gpsAccuracy = avgAcc;
                    if (_geometryType == GeoGeometryType.point) {
                      _points.clear();
                      _points.add(avgPoint);
                    } else {
                      _points.add(avgPoint);
                    }
                    _mapController.move(avgPoint, 17.5);
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Punto promediado con $samplesCount muestras satelitales (±${avgAcc.toStringAsFixed(1)}m)',
                      ),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                }
              });
            }

            final progress = samplesCount / targetSamples;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.satellite_alt, color: AppColors.primaryColor),
                  SizedBox(width: 8),
                  Text('Promediado Antiruido', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Capturando 10 muestras satelitales consecutivas para promediar la coordenada y eliminar rebotes.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: AppColors.primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Muestra $samplesCount de $targetSamples',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (samples.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Lectura actual: ±${samples.last.accuracy.toStringAsFixed(1)} m',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isCanceled = true;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Modo Caminado Continuo (Stream Tracking) para linderos y vías
  void _toggleStreamTracking() {
    HapticFeedback.mediumImpact();
    if (_isStreaming) {
      _stopStreamTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo "Caminar Lindero" finalizado.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } else {
      _startStreamTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚶 Caminando lindero: Vértices automáticos cada 2.5 metros.'),
          backgroundColor: Colors.indigo,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _startStreamTracking() {
    setState(() => _isStreaming = true);

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3, // Cada 3 metros
    );

    _streamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      if (!mounted || !_isStreaming) return;

      final newPoint = LatLng(position.latitude, position.longitude);
      HapticFeedback.selectionClick();

      setState(() {
        _currentGpsLocation = newPoint;
        _gpsAccuracy = position.accuracy;
        _points.add(newPoint);
        _mapController.move(newPoint, _mapController.camera.zoom);
      });
    });
  }

  void _stopStreamTracking() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  void _undoLastPoint() {
    if (_points.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _points.removeLast();
      });
    }
  }

  void _clearAllPoints() {
    if (_points.isNotEmpty) {
      HapticFeedback.heavyImpact();
      setState(() {
        _points.clear();
      });
    }
  }

  void _saveAndReturn() {
    if (_isStreaming) {
      _stopStreamTracking();
    }

    if (_points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor capture o dibuje al menos un punto en el mapa')),
      );
      return;
    }

    if (_geometryType == GeoGeometryType.line && _points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Una línea requiere al menos 2 puntos')),
      );
      return;
    }

    if (_geometryType == GeoGeometryType.polygon && _points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Un polígono requiere al menos 3 vértices')),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    final geoJsonMap = GisCalculator.toGeoJson(_geometryType, _points);
    final geoJsonStr = jsonEncode(geoJsonMap);
    Navigator.pop(context, geoJsonStr);
  }

  TileLayer _buildBaseTileLayer() {
    switch (_selectedBaseLayer) {
      case MapBaseLayer.satellite:
        return TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.surveygo',
          maxZoom: 19,
        );
      case MapBaseLayer.terrain:
        return TileLayer(
          urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.surveygo',
          maxZoom: 17,
        );
      case MapBaseLayer.mbtiles:
        final mbtilesService = MbtilesService();
        if (mbtilesService.isMbtilesAvailable) {
          return TileLayer(
            tileProvider: MbtilesTileProvider(),
            maxZoom: 20,
          );
        }
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.surveygo',
          maxZoom: 19,
        );
      case MapBaseLayer.streets:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.surveygo',
          maxZoom: 19,
        );
    }
  }

  void _showLayerSelectorDialog() {
    final mbtilesService = MbtilesService();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Seleccionar Capa de Mapa Base',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.map, color: Colors.blue),
                  title: const Text('OpenStreetMap (Calles)'),
                  trailing: _selectedBaseLayer == MapBaseLayer.streets
                      ? const Icon(Icons.check, color: AppColors.primaryColor)
                      : null,
                  onTap: () {
                    setState(() => _selectedBaseLayer = MapBaseLayer.streets);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.satellite_alt, color: Colors.green),
                  title: const Text('Satélite Mundial (ESRI World Imagery)'),
                  trailing: _selectedBaseLayer == MapBaseLayer.satellite
                      ? const Icon(Icons.check, color: AppColors.primaryColor)
                      : null,
                  onTap: () {
                    setState(() => _selectedBaseLayer = MapBaseLayer.satellite);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.terrain, color: Colors.brown),
                  title: const Text('Topográfico / Relieve (OpenTopoMap)'),
                  trailing: _selectedBaseLayer == MapBaseLayer.terrain
                      ? const Icon(Icons.check, color: AppColors.primaryColor)
                      : null,
                  onTap: () {
                    setState(() => _selectedBaseLayer = MapBaseLayer.terrain);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.offline_pin, color: Colors.orange),
                  title: Text(
                    mbtilesService.isMbtilesAvailable
                        ? 'MBTiles Offline (${mbtilesService.layerName})'
                        : 'MBTiles Offline (Cargar archivo .mbtiles)',
                  ),
                  subtitle: const Text(
                      'Mapa satelital/vector 100% offline para selva y zonas rurales'),
                  trailing: _selectedBaseLayer == MapBaseLayer.mbtiles
                      ? const Icon(Icons.check, color: AppColors.primaryColor)
                      : const Icon(Icons.folder_open, size: 20),
                  onTap: () async {
                    if (!mbtilesService.isMbtilesAvailable) {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['mbtiles', 'sqlite', 'db'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final ok =
                            await mbtilesService.loadMbtiles(result.files.single.path!);
                        if (ok && mounted) {
                          setState(() => _selectedBaseLayer = MapBaseLayer.mbtiles);
                        }
                      }
                    } else {
                      setState(() => _selectedBaseLayer = MapBaseLayer.mbtiles);
                    }
                    if (mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Retícula Táctica Central de Alta Precisión (Cruz de Topografía)
  Widget _buildCrosshair() {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Círculo exterior de precisión
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryColor.withValues(alpha: 0.85),
                width: 2.0,
              ),
            ),
          ),
          // Punto central rojo táctico
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          // Eje vertical superior
          Positioned(
            top: 0,
            child: Container(
              width: 2,
              height: 14,
              color: AppColors.primaryColor,
            ),
          ),
          // Eje vertical inferior
          Positioned(
            bottom: 0,
            child: Container(
              width: 2,
              height: 14,
              color: AppColors.primaryColor,
            ),
          ),
          // Eje horizontal izquierdo
          Positioned(
            left: 0,
            child: Container(
              width: 14,
              height: 2,
              color: AppColors.primaryColor,
            ),
          ),
          // Eje horizontal derecho
          Positioned(
            right: 0,
            child: Container(
              width: 14,
              height: 2,
              color: AppColors.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura Geoespacial'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Alternar Retícula de Precisión vs Toque Libre
          IconButton(
            tooltip: _useCrosshairMode ? 'Modo Retícula Activo' : 'Modo Toque Libre',
            icon: Icon(
              _useCrosshairMode ? Icons.filter_center_focus : Icons.touch_app,
              color: _useCrosshairMode ? Colors.amberAccent : Colors.white70,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _useCrosshairMode = !_useCrosshairMode;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_useCrosshairMode
                      ? '🎯 Modo Retícula: Mueva el mapa y presione "Fijar en Mira"'
                      : '👆 Modo Toque: Toque libremente en la pantalla'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Cambiar Capa Base',
            icon: const Icon(Icons.layers),
            onPressed: _showLayerSelectorDialog,
          ),
          IconButton(
            tooltip: 'Guardar Geometría',
            icon: const Icon(Icons.check, size: 28),
            onPressed: _saveAndReturn,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Mapa interactivo con soporte multicapa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 16.0,
              onTap: _handleMapTap,
              onPositionChanged: (camera, hasGesture) {
                _reticleCenterNotifier.value = camera.center;
              },
            ),
            children: [
              _buildBaseTileLayer(),
              // Capa de Polígonos
              if (_geometryType == GeoGeometryType.polygon && _points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: AppColors.primaryColor.withValues(alpha: 0.35),
                      borderColor: AppColors.primaryColor,
                      borderStrokeWidth: 3.0,
                    ),
                  ],
                ),
              // Capa de Líneas (Rutas o perímetro en progreso)
              if (_points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _points,
                      color: _geometryType == GeoGeometryType.polygon
                          ? Colors.orange
                          : AppColors.primaryColor,
                      strokeWidth: 3.5,
                    ),
                  ],
                ),
              // Capa de Marcadores / Vértices
              MarkerLayer(
                markers: [
                  ..._points.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    return Marker(
                      point: point,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _geometryType == GeoGeometryType.point
                              ? Colors.red
                              : AppColors.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: Center(
                          child: _geometryType == GeoGeometryType.point
                              ? const Icon(Icons.location_on,
                                  color: Colors.white, size: 18)
                              : Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    );
                  }),
                  // Marcador de ubicación GPS del usuario
                  if (_currentGpsLocation != null)
                    Marker(
                      point: _currentGpsLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. Retícula Central de Alta Precisión
          if (_useCrosshairMode)
            Center(
              child: IgnorePointer(
                child: _buildCrosshair(),
              ),
            ),

          // 3. Barra Superior de Tipo de Geometría & Pregunta
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Tarjeta con pregunta y aviso de modo GPS
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.help_outline, color: AppColors.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.questionText,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.allowGpsOnly)
                                const Text(
                                  '🔒 Modo Satélite Obligatorio (Solo botón "GPS")',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (_isStreaming)
                                const Text(
                                  '🚶 CAMINANDO LINDERO: Captura automática en curso...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Selector de Modo (Punto, Línea, Polígono)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTypeButton(GeoGeometryType.point, Icons.place, 'Punto'),
                      _buildTypeButton(
                          GeoGeometryType.line, Icons.timeline, 'Línea / Ruta'),
                      _buildTypeButton(
                          GeoGeometryType.polygon, Icons.crop_square, 'Polígono / Área'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Panel Inferior Táctico y Ergonómico (Thumb Zone)
          Positioned(
            bottom: 16,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Panel informativo de métricas y coordenadas vivas de la retícula
                _buildMetricsCard(),
                const SizedBox(height: 8),

                // Botón Principal de Pulgar: Fijar Vértice en la Mira (si está activa)
                if (_useCrosshairMode)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_location_alt, size: 22),
                      label: Text(
                        _geometryType == GeoGeometryType.point
                            ? 'Fijar Punto en la Mira Central'
                            : 'Fijar Vértice en la Mira Central (${_points.length + 1})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _addPointFromReticle,
                    ),
                  ),
                if (_useCrosshairMode) const SizedBox(height: 8),

                // Barra de Acciones Satelitales y de Edición
                Row(
                  children: [
                    // Botón Mi GPS (con opción de promediado)
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        icon: _isLoadingLocation
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: Text(
                          _gpsAccuracy != null
                              ? 'GPS (±${_gpsAccuracy!.toStringAsFixed(1)}m)'
                              : 'Mi GPS',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _addCurrentLocationPoint,
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Botón Promediar GPS (Antiruido)
                    IconButton(
                      tooltip: 'Promediar GPS (10 muestras)',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal.shade700,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.satellite_alt, size: 20),
                      onPressed: _startGpsAveraging,
                    ),
                    const SizedBox(width: 6),

                    // Modo Caminar Lindero (para Línea y Polígono)
                    if (_geometryType != GeoGeometryType.point) ...[
                      IconButton(
                        tooltip: _isStreaming
                            ? 'Detener caminado'
                            : 'Caminar lindero (Streaming continuo)',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              _isStreaming ? Colors.red.shade600 : Colors.white,
                          foregroundColor:
                              _isStreaming ? Colors.white : Colors.indigo.shade700,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          _isStreaming ? Icons.stop : Icons.directions_walk,
                          size: 20,
                        ),
                        onPressed: _toggleStreamTracking,
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Botón Deshacer
                    IconButton(
                      tooltip: 'Deshacer último punto',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.undo, size: 20),
                      onPressed: _points.isNotEmpty ? _undoLastPoint : null,
                    ),
                    const SizedBox(width: 6),

                    // Botón Limpiar
                    IconButton(
                      tooltip: 'Limpiar todo',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade700,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: _points.isNotEmpty ? _clearAllPoints : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(GeoGeometryType type, IconData icon, String label) {
    final isSelected = _geometryType == type;
    return GestureDetector(
      onTap: () {
        if (_geometryType != type) {
          HapticFeedback.selectionClick();
          setState(() {
            _geometryType = type;
            if (type == GeoGeometryType.point && _points.length > 1) {
              _points.removeRange(1, _points.length);
            }
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Coordenadas Vivas del Centro / Retícula
            ValueListenableBuilder<LatLng>(
              valueListenable: _reticleCenterNotifier,
              builder: (context, center, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🎯 Mira: ${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade800,
                      ),
                    ),
                    Text(
                      _points.isEmpty
                          ? '0 vértices'
                          : '${_points.length} ${_points.length == 1 ? "vértice" : "vértices"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 12),

            if (_geometryType == GeoGeometryType.point) ...[
              Text(
                _points.isNotEmpty
                    ? 'Punto fijado: Lat ${_points.first.latitude.toStringAsFixed(6)} | Lon ${_points.first.longitude.toStringAsFixed(6)}'
                    : (_useCrosshairMode
                        ? 'Apunte con la mira central y presione "Fijar Punto en la Mira"'
                        : 'Toque la pantalla o presione "Mi GPS" para fijar el punto'),
                style: TextStyle(
                  fontSize: 12,
                  color: _points.isNotEmpty ? Colors.black87 : Colors.grey.shade700,
                ),
              ),
            ],
            if (_geometryType == GeoGeometryType.line) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Longitud: ${GisCalculator.formatDistance(GisCalculator.calculateDistance(_points))}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    _points.length < 2 ? 'Falta 1 punto mín.' : 'Ruta lista',
                    style: TextStyle(
                      color: _points.length < 2 ? Colors.orange : Colors.green.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            if (_geometryType == GeoGeometryType.polygon) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Área: ${GisCalculator.formatArea(GisCalculator.calculatePolygonArea(_points))}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  Text(
                    'Perímetro: ${GisCalculator.formatDistance(GisCalculator.calculatePerimeter(_points))}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
