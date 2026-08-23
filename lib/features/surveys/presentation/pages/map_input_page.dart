import 'dart:convert';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _geometryType = widget.defaultGeometryType;

    _loadInitialGeometry();
    _fetchCurrentLocation();
  }

  void _loadInitialGeometry() {
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      final parsed = GisCalculator.fromGeoJsonOrString(widget.initialValue);
      if (parsed != null) {
        _geometryType = parsed.type;
        _points.addAll(parsed.points);
        if (_points.isNotEmpty) {
          _mapCenter = _points.first;
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
          desiredAccuracy: LocationAccuracy.high,
        );
        final userLatLng = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _currentGpsLocation = userLatLng;
            _gpsAccuracy = pos.accuracy;
            if (_points.isEmpty) {
              _mapCenter = userLatLng;
              _mapController.move(userLatLng, 16.0);
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

    setState(() {
      if (_geometryType == GeoGeometryType.point) {
        _points.clear();
        _points.add(latLng);
      } else {
        _points.add(latLng);
      }
    });
  }

  void _addCurrentLocationPoint() {
    if (_currentGpsLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obteniendo señal GPS del satélite... por favor espera')),
      );
      _fetchCurrentLocation();
      return;
    }

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

  void _undoLastPoint() {
    if (_points.isNotEmpty) {
      setState(() {
        _points.removeLast();
      });
    }
  }

  void _clearAllPoints() {
    if (_points.isNotEmpty) {
      setState(() {
        _points.clear();
      });
    }
  }

  void _saveAndReturn() {
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

    final geoJsonMap = GisCalculator.toGeoJson(_geometryType, _points);
    final geoJsonStr = jsonEncode(geoJsonMap);
    Navigator.pop(context, geoJsonStr);
  }

  TileLayer _buildBaseTileLayer() {
    switch (_selectedBaseLayer) {
      case MapBaseLayer.satellite:
        return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
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
        // Fallback a calles si no hay mbtiles cargado
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.surveygo',
          maxZoom: 19,
        );
      case MapBaseLayer.streets:
      default:
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
                  subtitle: const Text('Mapa satelital/vector 100% offline para selva y zonas rurales'),
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
                        final ok = await mbtilesService.loadMbtiles(result.files.single.path!);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura Geoespacial'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
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
              initialZoom: 15.0,
              onTap: _handleMapTap,
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
                              ? const Icon(Icons.location_on, color: Colors.white, size: 18)
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
                          color: Colors.blue.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. Barra Superior de Tipo de Geometría & Pregunta
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
                                  '🔒 Modo Satélite Obligatorio (Solo botón "Mi GPS")',
                                  style: TextStyle(
                                    fontSize: 11,
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
                      _buildTypeButton(GeoGeometryType.line, Icons.timeline, 'Línea / Ruta'),
                      _buildTypeButton(GeoGeometryType.polygon, Icons.crop_square, 'Polígono / Área'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Panel Inferior de Métricas GIS y Controles
          Positioned(
            bottom: 20,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Panel informativo de mediciones y precisión
                _buildMetricsCard(),
                const SizedBox(height: 10),
                // Botones de acción rápida
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isLoadingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(_gpsAccuracy != null
                            ? 'Mi GPS (±${_gpsAccuracy!.toStringAsFixed(1)}m)'
                            : 'Mi GPS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _addCurrentLocationPoint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _points.isNotEmpty ? _undoLastPoint : null,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Limpiar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_geometryType == GeoGeometryType.point) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Coordenadas del Punto:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    _gpsAccuracy != null ? 'Precisión: ±${_gpsAccuracy!.toStringAsFixed(1)} m' : '${_points.length} punto',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _points.isNotEmpty
                    ? 'Lat: ${_points.first.latitude.toStringAsFixed(6)} | Lng: ${_points.first.longitude.toStringAsFixed(6)}'
                    : (widget.allowGpsOnly
                        ? 'Presione "Mi GPS" para capturar la posición por satélite'
                        : 'Toque en el mapa para marcar el punto o use "Mi GPS"'),
                style: TextStyle(
                  fontSize: 13,
                  color: _points.isNotEmpty ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ],
            if (_geometryType == GeoGeometryType.line) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Distancia Total: ${GisCalculator.formatDistance(GisCalculator.calculateDistance(_points))}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('${_points.length} vértices',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _points.length < 2
                    ? 'Toque en el mapa para añadir vértices a la línea'
                    : 'Ruta trazada correctamente',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (_geometryType == GeoGeometryType.polygon) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Área: ${GisCalculator.formatArea(GisCalculator.calculatePolygonArea(_points))}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primaryColor)),
                  Text('${_points.length} vértices',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Perímetro: ${GisCalculator.formatDistance(GisCalculator.calculatePerimeter(_points))}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
