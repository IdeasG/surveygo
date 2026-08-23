import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
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

  @override
  void initState() {
    super.initState();
    _initLocation();
    final ws = widget.survey.workspace;
    final ly = widget.survey.layer;
    print('SurveyMapPage initState workspace=$ws layer=$ly');
    print('GeoServer base: ' + geoserverBaseUrl);
    if (ws.isNotEmpty && ly.isNotEmpty) {
      layerStates['$ws:$ly'] = true;
    }
    print('layerStates initialized: ' + layerStates.toString());
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _current = LatLng(pos.latitude, pos.longitude);
        _center = _current!;
      });
      // _mapController.move(_center, 15.0);
    }
  }

  List<Widget> getWmsTileLayers() {
    print('getWmsTileLayers layerStates: ' + layerStates.toString());
    final active = layerStates.entries.where((e) => e.value).toList();
    print('active layers: ' + active.map((e) => e.key).toList().toString());
    if (active.isEmpty) return [];
    final workspace = active.first.key.split(':').first;
    print('computed workspace: ' + workspace);
    final baseUrl = geoserverBaseUrl.replaceFirst('workspace', workspace);
    print('resolved baseUrl: ' + baseUrl);
    return active
        .map((entry) {
          print('adding WMS layer: ' + entry.key);
          return TileLayer(
            wmsOptions: WMSTileLayerOptions(
              baseUrl: baseUrl,
              layers: [entry.key],
              format: 'image/png',
              transparent: true,
              version: '1.1.0',
              styles: const [''],
              otherParameters: const {'srs': 'EPSG:4326'},
            ),
          );
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.survey.title),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: 6.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.surveygo',
          ),
          ...getWmsTileLayers(),
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
                    size: 32,
                  ),
                )
              ],
            ),
        ],
      ),
      floatingActionButton: _current == null
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              onPressed: () => _mapController.move(_center, 15.0),
              child: const Icon(Icons.center_focus_strong),
            ),
    );
  }
}
