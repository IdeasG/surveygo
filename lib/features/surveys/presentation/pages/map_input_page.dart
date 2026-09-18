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

  // Imán Magnético Topológico (Snapping de Vértices)
  bool _snappingEnabled = true;
  LatLng? _snappedPoint;

  LatLng? _findNearbySnap(LatLng center) {
    if (!_snappingEnabled || _points.isEmpty) return null;
    const distance = Distance();
    const double thresholdMeters = 6.0; // Umbral táctico de 6 metros

    LatLng? nearest;
    double minD = double.infinity;
    for (final p in _points) {
      final d = distance.as(LengthUnit.Meter, center, p);
      if (d <= thresholdMeters && d < minD) {
        minD = d;
        nearest = p;
      }
    }
    return nearest;
  }

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
      return;
    }

    if (widget.allowGpsOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta pregunta requiere captura satelital real. Use el botón "GPS".'),
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
    final target = _snappedPoint ?? _mapController.camera.center;

    if (_snappedPoint != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🧲 Vértice acoplado con imán topológico'),
          backgroundColor: Colors.green,
          duration: Duration(milliseconds: 1200),
        ),
      );
    }

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
                        'Punto fijado con $samplesCount muestras promediadas (±${avgAcc.toStringAsFixed(1)}m)',
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

  /// Diálogo interactivo para editar o eliminar un vértice específico
  void _showEditVertexDialog(int index) {
    HapticFeedback.mediumImpact();
    final point = _points[index];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vértice #${index + 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    Text(
                      'Lat: ${point.latitude.toStringAsFixed(6)}\nLng: ${point.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Divider(height: 20),
                ListTile(
                  leading: const Icon(Icons.filter_center_focus, color: Colors.amber),
                  title: const Text('Mover a la Mira Central Actual'),
                  subtitle: const Text('Reubica este vértice exactamente en la cruz'),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(ctx);
                    final newCenter = _mapController.camera.center;
                    setState(() {
                      _points[index] = newCenter;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Vértice #${index + 1} reubicado en la mira'),
                        backgroundColor: Colors.green.shade700,
                      ),
                    );
                  },
                ),
                if (_currentGpsLocation != null)
                  ListTile(
                    leading: const Icon(Icons.my_location, color: Colors.blue),
                    title: const Text('Mover a mi Ubicación GPS'),
                    subtitle: Text(
                      'Reubica este vértice a tu GPS (±${_gpsAccuracy?.toStringAsFixed(1) ?? "?"}m)',
                    ),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                      setState(() {
                        _points[index] = _currentGpsLocation!;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Vértice #${index + 1} reubicado a tu GPS'),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Eliminar solo este Vértice',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Borra este punto sin perder el resto del trazado'),
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    Navigator.pop(ctx);
                    setState(() {
                      _points.removeAt(index);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Vértice #${index + 1} eliminado'),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.help_outline, color: AppColors.primaryColor),
            SizedBox(width: 8),
            Text('Instrucciones de Captura', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('🎯 Modo Retícula:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Mueva el mapa bajo la cruz y presione "Fijar Vértice". No tapa la pantalla con el dedo.\n', style: TextStyle(fontSize: 12)),

            Text('✏️ Editar o Eliminar Vértice:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Toque cualquier número de vértice en el mapa para reubicarlo en la mira, moverlo a su GPS o borrarlo individualmente.\n', style: TextStyle(fontSize: 12)),

            Text('🚶 Modo Caminar Lindero:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Presione "Caminar" y recorra el perímetro. Los vértices se capturarán automáticamente cada 2.5 metros.\n', style: TextStyle(fontSize: 12)),

            Text('📡 Promediado GPS (10x):', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Toma 10 lecturas consecutivas para filtrar rebotes en zonas boscosas o urbanas.', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Retícula Táctica Central de Alta Precisión (Cruz de Topografía con Imán)
  Widget _buildCrosshair() {
    final isSnapped = _snappedPoint != null;
    final color = isSnapped ? Colors.greenAccent.shade700 : AppColors.primaryColor;

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isSnapped)
            Positioned(
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Text(
                  '🧲 IMÁN',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // Círculo exterior de precisión
          Container(
            width: isSnapped ? 48 : 44,
            height: isSnapped ? 48 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: isSnapped ? 1.0 : 0.85),
                width: isSnapped ? 3.0 : 2.0,
              ),
              boxShadow: isSnapped
                  ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
          ),
          // Punto central táctico
          Container(
            width: isSnapped ? 10 : 8,
            height: isSnapped ? 10 : 8,
            decoration: BoxDecoration(
              color: isSnapped ? Colors.greenAccent.shade700 : Colors.redAccent,
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
            top: isSnapped ? 14 : 8,
            child: Container(
              width: isSnapped ? 3 : 2,
              height: 12,
              color: color,
            ),
          ),
          // Eje vertical inferior
          Positioned(
            bottom: 8,
            child: Container(
              width: isSnapped ? 3 : 2,
              height: 12,
              color: color,
            ),
          ),
          // Eje horizontal izquierdo
          Positioned(
            left: 8,
            child: Container(
              width: 12,
              height: isSnapped ? 3 : 2,
              color: color,
            ),
          ),
          // Eje horizontal derecho
          Positioned(
            right: 8,
            child: Container(
              width: 12,
              height: isSnapped ? 3 : 2,
              color: color,
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
          // Alternar Imán Magnético Topológico
          IconButton(
            tooltip: _snappingEnabled ? 'Imán Topológico Activo' : 'Imán Desactivado',
            icon: Icon(
              Icons.attractions,
              color: _snappingEnabled ? Colors.greenAccent : Colors.white70,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _snappingEnabled = !_snappingEnabled;
                if (!_snappingEnabled) _snappedPoint = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_snappingEnabled
                      ? '🧲 Imán Activado: Acople automático a vértices colindantes'
                      : 'Imán Desactivado'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          // Guía / Ayuda
          IconButton(
            tooltip: 'Guía de uso',
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
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
                final center = camera.center;
                if (_snappingEnabled) {
                  final snap = _findNearbySnap(center);
                  if (snap != null) {
                    if (_snappedPoint != snap) {
                      HapticFeedback.selectionClick();
                    }
                    if (_snappedPoint != snap) {
                      setState(() => _snappedPoint = snap);
                    }
                    _reticleCenterNotifier.value = snap;
                    return;
                  } else if (_snappedPoint != null) {
                    setState(() => _snappedPoint = null);
                  }
                }
                _reticleCenterNotifier.value = center;
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
              // Capa de Marcadores / Vértices Interactivos (Tocar para editar/eliminar)
              MarkerLayer(
                markers: [
                  ..._points.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    return Marker(
                      point: point,
                      width: 36,
                      height: 36,
                      child: GestureDetector(
                        onTap: () => _showEditVertexDialog(index),
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

          // 3. Banner Informativo Superior
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Tarjeta con pregunta y aviso de modo GPS
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.help_outline, color: AppColors.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.questionText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.allowGpsOnly)
                                const Text(
                                  '🔒 Modo Satélite Obligatorio',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
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
                const SizedBox(height: 4),
                // Selector de Modo (Punto, Línea, Polígono)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
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

          // 4. Banner Alerta si el Modo Caminar Lindero está Activo
          if (_isStreaming)
            Positioned(
              top: 108,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.shade700,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_walk, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CAMINANDO LINDERO (${_points.length} vértices)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _stopStreamTracking,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        child: const Text(
                          'DETENER',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 5. Panel Inferior Ergonómico Protegido por SafeArea (Nunca tapado por Android Bar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A. Métricas compactas
                    _buildMetricsCard(),
                    const SizedBox(height: 6),

                    // B. Fila de Acción Primaria (Fijar en Mira + Deshacer + Limpiar)
                    Row(
                      children: [
                        // Botón Principal de Pulgar: Fijar Vértice en la Mira
                        Expanded(
                          flex: 5,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add_location_alt, size: 20),
                            label: Text(
                              _geometryType == GeoGeometryType.point
                                  ? 'Fijar Punto'
                                  : 'Fijar en Mira (${_points.length + 1})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _useCrosshairMode ? _addPointFromReticle : null,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Botón Deshacer
                        ElevatedButton.icon(
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Deshacer', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _points.isNotEmpty ? _undoLastPoint : null,
                        ),
                        const SizedBox(width: 6),

                        // Botón Limpiar Todo
                        ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _points.isNotEmpty ? _clearAllPoints : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // C. Fila Satelital & Herramientas Especiales (GPS, Promediar, Caminar)
                    Row(
                      children: [
                        // Botón Mi GPS
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: _isLoadingLocation
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location, size: 15),
                            label: Text(
                              _gpsAccuracy != null
                                  ? 'GPS ±${_gpsAccuracy!.toStringAsFixed(0)}m'
                                  : 'Mi GPS',
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blue.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _addCurrentLocationPoint,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Botón Promediar GPS (10x)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.satellite_alt, size: 15),
                            label: const Text('Promediar 10x', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.teal.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _startGpsAveraging,
                          ),
                        ),

                        // Botón Caminar Lindero (Stream continuo)
                        if (_geometryType != GeoGeometryType.point) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: Icon(
                                _isStreaming ? Icons.stop : Icons.directions_walk,
                                size: 15,
                              ),
                              label: Text(
                                _isStreaming ? 'Detener' : 'Caminar',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isStreaming
                                    ? Colors.red.shade600
                                    : Colors.indigo.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _toggleStreamTracking,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fila 1: Coordenada de la Mira + Conteo de Vértices
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
                        color: Colors.blueGrey.shade900,
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

            // Fila 2: Mediciones calculadas (Área / Perímetro / Longitud)
            if (_geometryType == GeoGeometryType.polygon && _points.length >= 3) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Área: ${GisCalculator.formatArea(GisCalculator.calculatePolygonArea(_points))}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  Text(
                    'Perímetro: ${GisCalculator.formatDistance(GisCalculator.calculatePerimeter(_points))}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ],
            if (_geometryType == GeoGeometryType.line && _points.length >= 2) ...[
              const SizedBox(height: 4),
              Text(
                'Longitud: ${GisCalculator.formatDistance(GisCalculator.calculateDistance(_points))}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
            if (_points.isNotEmpty && _geometryType != GeoGeometryType.point) ...[
              const SizedBox(height: 2),
              Text(
                '💡 Tip: Toca cualquier número en el mapa para moverlo o borrarlo.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
