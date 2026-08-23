import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/features/surveys/presentation/pages/survey_detail_page.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/env.dart';

class SurveyMapPage extends StatefulWidget {
  final SurveyModel survey;

  const SurveyMapPage({Key? key, required this.survey}) : super(key: key);

  @override
  State<SurveyMapPage> createState() => _SurveyMapPageState();
}

class _SurveyMapPageState extends State<SurveyMapPage> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(-12.04318, -75.02824);
  LatLng? _current;
  final Map<String, bool> layerStates = {};

  // Entidad seleccionada para inspección longitudinal
  Map<String, dynamic>? _selectedEntity;

  @override
  void initState() {
    super.initState();
    _initLocation();
    final ws = widget.survey.workspace;
    final ly = widget.survey.layer;
    if (ws.isNotEmpty && ly.isNotEmpty) {
      layerStates['$ws:$ly'] = true;
    }
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        if (mounted) {
          setState(() {
            _current = LatLng(pos.latitude, pos.longitude);
            _center = _current!;
          });
        }
      }
    } catch (_) {}
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    // Simulación / consulta de entidad espacial tocada en mapa
    setState(() {
      _selectedEntity = {
        'codigo': 'PRED-${point.latitude.toStringAsFixed(4)}-${point.longitude.toStringAsFixed(4)}',
        'lat': point.latitude,
        'lng': point.longitude,
        'tipo': 'Lote Catastral / Predio',
        'ultima_inspeccion': 'Pendiente de Actualización',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa: ${widget.survey.title}'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_current != null) {
                _mapController.move(_current!, 16.0);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15.0,
              onTap: _handleMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.ideasg.surveygo',
              ),
              if (_current != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _current!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                    if (_selectedEntity != null)
                      Marker(
                        point: LatLng(_selectedEntity!['lat'], _selectedEntity!['lng']),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 36,
                        ),
                      ),
                  ],
                ),
            ],
          ),

          // Tarjeta flotante de Entidad Seleccionada (Estilo ODK Entities / Case Management)
          if (_selectedEntity != null)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.between,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.domain, color: Colors.blue, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                _selectedEntity!['codigo'],
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _selectedEntity = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tipo: ${_selectedEntity!['tipo']} | Coord: ${_selectedEntity!['lat'].toStringAsFixed(4)}, ${_selectedEntity!['lng'].toStringAsFixed(4)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.assignment_add),
                          label: const Text(
                            '📝 Nueva Inspección / Actualización',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SurveyDetailPage(survey: widget.survey),
                              ),
                            );
                          },
                        ),
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
}
