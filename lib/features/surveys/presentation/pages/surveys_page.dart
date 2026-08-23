import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';
import 'package:surveygo/features/surveys/presentation/pages/survey_detail_page.dart';
import 'package:surveygo/features/surveys/presentation/widgets/survey_card.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/survey_sync_service.dart';

class SurveysPage extends StatefulWidget {
  const SurveysPage({Key? key}) : super(key: key);

  @override
  State<SurveysPage> createState() => _SurveysPageState();
}

class _SurveysPageState extends State<SurveysPage> {
  bool _isLoading = false;
  bool _isSyncing = false;
  String _userName = 'Encuestador';
  int _pendingDraftsCount = 0;
  List<SurveyModel> _allSurveys = [];
  List<SurveyModel> _filteredSurveys = [];
  String _searchQuery = '';
  String _selectedFilter = 'TODOS'; // 'TODOS', 'POLYGON', 'LINE', 'POINT'

  final SurveySyncService _syncService = SurveySyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    // Inicializar inmediatamente las plantillas para carga instantánea
    _allSurveys = _getFallbackSurveys();
    _applyFilters();
    _isLoading = false;

    _loadUserInfo();
    _loadSurveys();
  }

  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('username') ?? 'Encuestador';
      final drafts = await _dbHelper.getAllSubmissionsGrouped(statusFilter: 'DRAFT').timeout(
        const Duration(seconds: 2),
        onTimeout: () => [],
      );
      if (mounted) {
        setState(() {
          _userName = name;
          _pendingDraftsCount = drafts.length;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar info de usuario: $e');
    }
  }

  Future<void> _loadSurveys() async {
    try {
      final localSurveys = await _syncService.getLocalSurveysWithQuestions().timeout(
        const Duration(seconds: 3),
        onTimeout: () => [],
      );

      if (localSurveys.isNotEmpty) {
        final converted = localSurveys.map((r) => _convertToSurveyModel(r)).toList();
        if (mounted) {
          setState(() {
            _allSurveys = converted;
            _applyFilters();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error cargando encuestas: $e');
      if (mounted) {
        setState(() {
          _allSurveys = _getFallbackSurveys();
          _applyFilters();
          _isLoading = false;
        });
      }
    }
  }

  List<SurveyModel> _getFallbackSurveys() {
    return [
      SurveyModel(
        id: 101,
        title: 'Censo Urbano & Catastro Predial',
        description: 'Delimitación de predios, cálculo de área en m², servicios y fotos.',
        type: 'POLYGON',
        questions: [
          QuestionModel(
            id: 1001,
            field: 'titular',
            text: 'Nombre Completo del Titular o Conductor',
            type: 'TEXT',
            isRequired: true,
            hint: 'Ej: Juan Pérez Gómez',
            options: [],
          ),
          QuestionModel(
            id: 1002,
            field: 'uso_suelo',
            text: 'Uso Predominante del Predio',
            type: 'SELECTIONSIMPLE',
            isRequired: true,
            options: [
              OptionModel(id: 1, text: 'Vivienda / Residencial'),
              OptionModel(id: 2, text: 'Comercial'),
              OptionModel(id: 3, text: 'Industrial / Taller'),
              OptionModel(id: 4, text: 'Educación / Salud'),
              OptionModel(id: 5, text: 'Terreno Vacante'),
            ],
          ),
          QuestionModel(
            id: 1003,
            field: 'poligono_predio',
            text: 'Delimitación y Área del Predio (Polígono)',
            type: 'POLYGON',
            isRequired: true,
            geometryType: 'POLYGON',
            hint: 'Dibuje el perímetro en el mapa o marque los vértices con GPS',
            options: [],
          ),
          QuestionModel(
            id: 1004,
            field: 'servicios',
            text: 'Servicios Básicos Instalados',
            type: 'SELECTIONMULTIPLE',
            options: [
              OptionModel(id: 1, text: 'Agua Potable'),
              OptionModel(id: 2, text: 'Alcantarillado'),
              OptionModel(id: 3, text: 'Energía Eléctrica'),
              OptionModel(id: 4, text: 'Gas Natural / Red'),
            ],
          ),
          QuestionModel(
            id: 1005,
            field: 'foto_fachada',
            text: 'Fotografía de la Fachada Principal',
            type: 'PHOTO',
            isRequired: true,
            options: [],
          ),
          QuestionModel(
            id: 1006,
            field: 'firma_inspector',
            text: 'Firma de Conformidad del Inspector',
            type: 'SIGNATURE',
            isRequired: true,
            options: [],
          ),
        ],
      ),
      SurveyModel(
        id: 102,
        title: 'Inspección Vial y Redes de Transporte',
        description: 'Trazado continuo de rutas, cálculo de longitud y estado del pavimento.',
        type: 'LINE',
        questions: [
          QuestionModel(
            id: 2001,
            field: 'nombre_via',
            text: 'Nombre de la Vía / Avenida / Tramo',
            type: 'TEXT',
            isRequired: true,
            hint: 'Ej: Av. Los Libertadores Tramo 2',
            options: [],
          ),
          QuestionModel(
            id: 2002,
            field: 'trazo_ruta',
            text: 'Trazado y Longitud del Tramo (Ruta)',
            type: 'LINE',
            isRequired: true,
            geometryType: 'LINESTRING',
            hint: 'Trace la línea continua de la vía en el mapa',
            options: [],
          ),
          QuestionModel(
            id: 2003,
            field: 'tipo_pavimento',
            text: 'Tipo de Superficie de Rodadura',
            type: 'SELECTIONSIMPLE',
            isRequired: true,
            options: [
              OptionModel(id: 1, text: 'Asfalto en Caliente'),
              OptionModel(id: 2, text: 'Concreto Hidráulico'),
              OptionModel(id: 3, text: 'Adoquinado'),
              OptionModel(id: 4, text: 'Afirmado / Trocha'),
            ],
          ),
          QuestionModel(
            id: 2004,
            field: 'estado_conservacion',
            text: 'Estado de Conservación de la Vía',
            type: 'SELECTIONSIMPLE',
            isRequired: true,
            options: [
              OptionModel(id: 1, text: 'Excelente / Nuevo'),
              OptionModel(id: 2, text: 'Bueno (Baches menores)'),
              OptionModel(id: 3, text: 'Regular (Desgaste superficial)'),
              OptionModel(id: 4, text: 'Crítico (Requiere recapeo total)'),
            ],
          ),
          QuestionModel(
            id: 2005,
            field: 'foto_evidencia',
            text: 'Foto del Estado de la Vía',
            type: 'PHOTO',
            options: [],
          ),
        ],
      ),
      SurveyModel(
        id: 103,
        title: 'Inventario Rápido de Mobiliario y Equipamiento',
        description: 'Georreferenciación puntual con GPS de postes, hidrantes y semáforos.',
        type: 'POINT',
        questions: [
          QuestionModel(
            id: 3001,
            field: 'tipo_elemento',
            text: 'Tipo de Equipamiento / Mobiliario',
            type: 'SELECTIONSIMPLE',
            isRequired: true,
            options: [
              OptionModel(id: 1, text: 'Poste de Alumbrado LED'),
              OptionModel(id: 2, text: 'Hidrante contra Incendios'),
              OptionModel(id: 3, text: 'Semáforo Vehicular'),
              OptionModel(id: 4, text: 'Cámara de Seguridad Urbana'),
            ],
          ),
          QuestionModel(
            id: 3002,
            field: 'ubicacion_gps',
            text: 'Posición GPS del Elemento',
            type: 'MAP',
            isRequired: true,
            geometryType: 'POINT',
            allowGpsOnly: true,
            hint: 'Presione "Mi GPS" para georreferenciar',
            options: [],
          ),
          QuestionModel(
            id: 3003,
            field: 'estado_operativo',
            text: 'Estado de Funcionamiento',
            type: 'SELECTIONSIMPLE',
            isRequired: true,
            options: [
              OptionModel(id: 1, text: 'Operativo al 100%'),
              OptionModel(id: 2, text: 'Mantenimiento Preventivo Requerido'),
              OptionModel(id: 3, text: 'Inoperativo / Averiado'),
            ],
          ),
          QuestionModel(
            id: 3004,
            field: 'foto_elemento',
            text: 'Fotografía del Elemento',
            type: 'PHOTO',
            options: [],
          ),
        ],
      ),
    ];
  }

  Future<void> _syncWithServer() async {
    setState(() => _isSyncing = true);
    final success = await _syncService.syncSurveys();
    await _loadSurveys();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '✅ Formularios sincronizados con GLGIS'
              : 'ℹ️ No se pudo conectar al servidor. Mostrando encuestas locales.'),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  SurveyModel _convertToSurveyModel(SurveyRolModel rolSurvey) {
    return SurveyModel(
      id: rolSurvey.id,
      title: rolSurvey.cNombreEncuesta,
      description: 'Tipo de Geometría: ${rolSurvey.cTipo}',
      type: rolSurvey.cTipo,
      workspace: rolSurvey.fuenteDatos?.cWorkspace ?? '',
      layer: rolSurvey.fuenteDatos?.cCapa ?? '',
      questions: rolSurvey.preguntas
          .map((p) => QuestionModel.fromSurveyQuestionModel(p))
          .toList(),
      isCompleted: false,
    );
  }

  void _applyFilters() {
    List<SurveyModel> result = _allSurveys;

    if (_selectedFilter != 'TODOS') {
      result = result.where((s) {
        final t = s.type.toUpperCase();
        if (_selectedFilter == 'POLYGON') return t.contains('POLYGON') || t.contains('AREA');
        if (_selectedFilter == 'LINE') return t.contains('LINE') || t.contains('RUTA');
        if (_selectedFilter == 'POINT') return t.contains('POINT') || t.contains('PUNTO') || t.contains('GPS');
        return true;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result.where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    setState(() {
      _filteredSurveys = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Levantamiento de Información'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sincronizar Formularios con GLGIS',
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync),
            onPressed: _isSyncing ? null : _syncWithServer,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserInfo();
          await _loadSurveys();
        },
        child: Column(
          children: [
            // 1. Header Banner de Bienvenida & Métricas
            _buildWelcomeBanner(),

            // 2. Buscador y Filtros Rápidos
            _buildSearchAndFilters(),

            // 3. Lista de Encuestas
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryColor))
                  : _filteredSurveys.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          itemCount: _filteredSurveys.length,
                          itemBuilder: (context, index) {
                            final survey = _filteredSurveys[index];
                            return SurveyCard(
                              survey: survey,
                              onTap: () async {
                                final res = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SurveyDetailPage(survey: survey),
                                  ),
                                );
                                if (res == true) {
                                  _loadUserInfo();
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola, $_userName!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Selecciona un formulario para recolectar datos',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.offline_pin, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Modo Offline', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Métricas Rápidas
          Row(
            children: [
              _buildMetricChip(Icons.folder_open, '${_allSurveys.length} Formularios', Colors.white),
              const SizedBox(width: 10),
              if (_pendingDraftsCount > 0)
                _buildMetricChip(Icons.edit_note, '$_pendingDraftsCount Borradores', Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // Campo de búsqueda
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar formulario o tipo...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            onChanged: (val) {
              _searchQuery = val;
              _applyFilters();
            },
          ),
          const SizedBox(height: 12),
          // Chips de filtro espacial
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('TODOS', 'Todos', Icons.grid_view),
                const SizedBox(width: 8),
                _buildFilterChip('POLYGON', 'Polígonos / Áreas', Icons.crop_square),
                const SizedBox(width: 8),
                _buildFilterChip('LINE', 'Rutas / Vías', Icons.timeline),
                const SizedBox(width: 8),
                _buildFilterChip('POINT', 'Puntos GPS', Icons.place),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : Colors.grey.shade700,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primaryColor,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey.shade800,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) {
        setState(() {
          _selectedFilter = key;
          _applyFilters();
        });
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No se encontraron formularios',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba cambiando el filtro de búsqueda o pulsa el botón para descargar encuestas del servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text('Descargar Encuestas del Servidor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _syncWithServer,
            ),
          ],
        ),
      ),
    );
  }
}
