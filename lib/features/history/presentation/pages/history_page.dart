import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/features/surveys/presentation/pages/survey_detail_page.dart';
import 'package:surveygo/services/database_helper.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;
  bool _showMapView = false;

  List<Map<String, dynamic>> _draftSubmissions = [];
  List<Map<String, dynamic>> _completedSubmissions = [];
  List<Map<String, dynamic>> _syncedSubmissions = [];

  // Geometrías para la vista de mapa
  final List<({String id, String title, String status, GeoGeometryType type, List<LatLng> points})> _mapGeometries = [];
  LatLng _mapCenter = const LatLng(-12.04318, -75.02824);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final allGrouped = await _dbHelper.getAllSubmissionsGrouped();
      final drafts = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      final synced = <Map<String, dynamic>>[];
      final geoms = <({String id, String title, String status, GeoGeometryType type, List<LatLng> points})>[];

      for (var sub in allGrouped) {
        final status = (sub['status'] ?? 'COMPLETED').toString().toUpperCase();
        if (status == 'DRAFT') {
          drafts.add(sub);
        } else if (status == 'SYNCED') {
          synced.add(sub);
        } else {
          completed.add(sub);
        }

        // Extraer geometría para el mapa si existe
        final glgisRaw = sub['glgis_sample']?.toString();
        if (glgisRaw != null && glgisRaw.isNotEmpty) {
          final parsed = GisCalculator.fromGeoJsonOrString(glgisRaw);
          if (parsed != null && parsed.points.isNotEmpty) {
            geoms.add((
              id: sub['response_set_id'].toString(),
              title: sub['nombre_encuesta'].toString(),
              status: status,
              type: parsed.type,
              points: parsed.points,
            ));
          }
        }
      }

      LatLng newCenter = _mapCenter;
      if (geoms.isNotEmpty && geoms.first.points.isNotEmpty) {
        newCenter = geoms.first.points.first;
      }

      if (mounted) {
        setState(() {
          _draftSubmissions = drafts;
          _completedSubmissions = completed;
          _syncedSubmissions = synced;
          _mapGeometries.clear();
          _mapGeometries.addAll(geoms);
          _mapCenter = newCenter;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando historial: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSubmission(String responseSetId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Registro'),
        content: const Text('¿Estás seguro de que deseas eliminar este registro localmente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbHelper.deleteResponseSet(responseSetId);
      _loadHistory();
    }
  }

  Future<void> _openSubmissionDetail(Map<String, dynamic> submission) async {
    final responseSetId = submission['response_set_id'].toString();
    final responses = await _dbHelper.getResponsesBySetId(responseSetId);
    final isDraft = (submission['status'] ?? '').toString().toUpperCase() == 'DRAFT';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          submission['nombre_encuesta'] ?? 'Detalle de Encuesta',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      _buildStatusBadge(submission['status']),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fecha: ${submission['fecha_creacion'] ?? 'Reciente'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: responses.length,
                      itemBuilder: (_, idx) {
                        final item = responses[idx];
                        return _buildResponseDetailTile(item);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (isDraft)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('Continuar Editando'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final surveyId = int.tryParse(submission['id_encuesta'].toString()) ?? 0;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SurveyDetailPage(
                                    survey: SurveyModel(
                                      id: surveyId,
                                      title: submission['nombre_encuesta'] ?? '',
                                      description: '',
                                      questions: [],
                                    ),
                                    existingResponseSetId: responseSetId,
                                  ),
                                ),
                              );
                              _loadHistory();
                            },
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteSubmission(responseSetId);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildResponseDetailTile(Map<String, dynamic> item) {
    final respText = item['c_respuesta']?.toString() ?? '';
    final glgisText = item['glgis']?.toString() ?? '';
    final fileType = (item['c_tipo_pregunta'] ?? '').toString().toUpperCase();

    Widget contentWidget;

    if (glgisText.isNotEmpty) {
      final parsed = GisCalculator.fromGeoJsonOrString(glgisText);
      if (parsed != null) {
        String info = '';
        if (parsed.type == GeoGeometryType.point) {
          info = 'Punto: ${parsed.points.first.latitude.toStringAsFixed(5)}, ${parsed.points.first.longitude.toStringAsFixed(5)}';
        } else if (parsed.type == GeoGeometryType.line) {
          info = 'Línea: ${GisCalculator.formatDistance(GisCalculator.calculateDistance(parsed.points))} (${parsed.points.length} pts)';
        } else {
          info = 'Polígono: ${GisCalculator.formatArea(GisCalculator.calculatePolygonArea(parsed.points))} (${parsed.points.length} vtx)';
        }
        contentWidget = Row(
          children: [
            const Icon(Icons.place, color: AppColors.primaryColor, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(info, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        );
      } else {
        contentWidget = Text(glgisText);
      }
    } else if (fileType == 'PHOTO' && respText.isNotEmpty && File(respText).existsSync()) {
      contentWidget = Image.file(File(respText), height: 100, fit: BoxFit.cover);
    } else {
      contentWidget = Text(respText.isNotEmpty ? respText : '(Sin respuesta)');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pregunta #${item['id_pregunta']} (${item['c_tipo_pregunta']})',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            contentWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(dynamic status) {
    final s = (status ?? 'COMPLETED').toString().toUpperCase();
    Color color = Colors.green;
    String label = 'Completada';

    if (s == 'DRAFT') {
      color = Colors.orange;
      label = 'Borrador';
    } else if (s == 'SYNCED') {
      color = Colors.blue;
      label = 'Sincronizada';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial y Envíos'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _showMapView ? 'Ver Lista' : 'Ver Mapa de Levantamientos',
            icon: Icon(_showMapView ? Icons.view_list : Icons.map),
            onPressed: () => setState(() => _showMapView = !_showMapView),
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
        bottom: _showMapView
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: 'Borradores (${_draftSubmissions.length})'),
                  Tab(text: 'Listos (${_completedSubmissions.length})'),
                  Tab(text: 'Sincronizados (${_syncedSubmissions.length})'),
                ],
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showMapView
              ? _buildGeneralMapView()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSubmissionsList(_draftSubmissions, isDraftList: true),
                    _buildSubmissionsList(_completedSubmissions),
                    _buildSubmissionsList(_syncedSubmissions),
                  ],
                ),
    );
  }

  Widget _buildSubmissionsList(List<Map<String, dynamic>> list, {bool isDraftList = false}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              isDraftList ? 'No tienes borradores pendientes' : 'No hay registros en esta sección',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final item = list[idx];
        final hasGis = item['glgis_sample'] != null && item['glgis_sample'].toString().isNotEmpty;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isDraftList ? Colors.orange.shade100 : AppColors.primaryColor.withValues(alpha: 0.15),
              child: Icon(
                hasGis ? Icons.pin_drop : Icons.assignment,
                color: isDraftList ? Colors.orange.shade800 : AppColors.primaryColor,
              ),
            ),
            title: Text(
              item['nombre_encuesta'] ?? 'Encuesta',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Fecha: ${item['fecha_creacion'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text('${item['total_respuestas']} campos respondidos', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
            trailing: _buildStatusBadge(item['status']),
            onTap: () => _openSubmissionDetail(item),
          ),
        );
      },
    );
  }

  Widget _buildGeneralMapView() {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _mapCenter,
            initialZoom: 14.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.surveygo',
            ),
            // Polígonos de todas las encuestas
            PolygonLayer(
              polygons: _mapGeometries
                  .where((g) => g.type == GeoGeometryType.polygon)
                  .map((g) {
                Color color = g.status == 'DRAFT'
                    ? Colors.orange
                    : (g.status == 'SYNCED' ? Colors.blue : AppColors.primaryColor);
                return Polygon(
                  points: g.points,
                  color: color.withValues(alpha: 0.3),
                  borderColor: color,
                  borderStrokeWidth: 2.5,
                );
              }).toList(),
            ),
            // Líneas de todas las encuestas
            PolylineLayer(
              polylines: _mapGeometries
                  .where((g) => g.type == GeoGeometryType.line)
                  .map((g) {
                Color color = g.status == 'DRAFT'
                    ? Colors.orange
                    : (g.status == 'SYNCED' ? Colors.blue : AppColors.primaryColor);
                return Polyline(
                  points: g.points,
                  color: color,
                  strokeWidth: 3.5,
                );
              }).toList(),
            ),
            // Marcadores de puntos
            MarkerLayer(
              markers: _mapGeometries.map((g) {
                Color color = g.status == 'DRAFT'
                    ? Colors.orange
                    : (g.status == 'SYNCED' ? Colors.blue : Colors.red);
                final pt = g.points.first;
                return Marker(
                  point: pt,
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${g.title} (${g.status})')),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Icon(
                        g.type == GeoGeometryType.polygon
                            ? Icons.crop_square
                            : (g.type == GeoGeometryType.line ? Icons.timeline : Icons.location_on),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Leyenda del mapa
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Leyenda:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                _buildLegendItem(Colors.orange, 'Borradores'),
                _buildLegendItem(AppColors.primaryColor, 'Listos para enviar'),
                _buildLegendItem(Colors.blue, 'Sincronizados'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
