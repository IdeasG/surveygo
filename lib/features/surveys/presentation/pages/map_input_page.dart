import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapInputPage extends StatefulWidget {
  final String? initialValue;
  final String questionText;

  const MapInputPage({
    Key? key,
    this.initialValue,
    required this.questionText,
  }) : super(key: key);

  @override
  State<MapInputPage> createState() => _MapInputPageState();
}

class _MapInputPageState extends State<MapInputPage> {
  late LatLng _selectedPosition;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Inicializar con un valor por defecto o el valor guardado
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      try {
        final parts = widget.initialValue!.split(',');
        if (parts.length == 2) {
          _selectedPosition = LatLng(
            double.parse(parts[0]),
            double.parse(parts[1]),
          );
        } else {
          _selectedPosition =
              LatLng(-12.06, -77.0375); // Ciudad de Lima como default
        }
      } catch (e) {
        _selectedPosition =
            LatLng(-12.06, -77.0375); // Ciudad de Lima como default
      }
    } else {
      _selectedPosition =
          LatLng(-12.06, -77.0375); // Ciudad de Lima como default
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Seleccionar ubicación'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              widget.questionText,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _selectedPosition,
                zoom: 6.0,
                onTap: (tapPosition, latLng) {
                  setState(() {
                    _selectedPosition = latLng;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.surveygo',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                      width: 40.0,
                      height: 40.0,
                      point: _selectedPosition,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  'Lat: ${_selectedPosition.latitude.toStringAsFixed(6)}\nLng: ${_selectedPosition.longitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 16),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Devolver la ubicación seleccionada
                    Navigator.pop(context,
                        '${_selectedPosition.longitude},${_selectedPosition.latitude}');
                  },
                  child: Text('Guardar ubicación'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
