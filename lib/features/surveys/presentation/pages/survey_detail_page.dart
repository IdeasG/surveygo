import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:signature/signature.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';
import 'package:surveygo/core/utils/watermark_service.dart';
import 'package:surveygo/features/surveys/presentation/pages/map_input_page.dart';
import 'package:surveygo/services/database_helper.dart';

class SurveyDetailPage extends StatefulWidget {
  final SurveyModel survey;
  final String? existingResponseSetId;

  const SurveyDetailPage({
    Key? key,
    required this.survey,
    this.existingResponseSetId,
  }) : super(key: key);

  @override
  State<SurveyDetailPage> createState() => _SurveyDetailPageState();
}

class _SurveyDetailPageState extends State<SurveyDetailPage> {
  bool _isLoading = true;
  List<QuestionModel> _questions = [];
  String? _currentResponseSetId;
  String _currentStatus = 'DRAFT';
  final Map<int, String> _validationErrors = {};

  // Auditoría e Integridad Antifraude (Estilo SurveyCTO)
  final DateTime _startTime = DateTime.now();
  double _gpsAccuracy = 0.0;
  LatLng? _initialGpsLocation;

  // Ubicación actual
  LatLng _currentLocation = const LatLng(-12.04318, -75.02824);
  bool _isRuralZone = false;

  // Filtro de secciones
  String? _selectedSection;
  List<String> _availableSections = [];

  @override
  void initState() {
    super.initState();
    _currentResponseSetId = widget.existingResponseSetId;

    // 1. Carga inmediata de las preguntas del modelo para cero latencia
    _questions = List<QuestionModel>.from(widget.survey.questions);
    final sections = <String>{};
    for (var q in _questions) {
      if (q.section != null && q.section!.isNotEmpty) {
        sections.add(q.section!);
      }
    }
    _availableSections = sections.toList();
    if (_availableSections.isNotEmpty) {
      _selectedSection = _availableSections.first;
    }
    _isLoading = false;

    // 2. Carga asíncrona de respuestas previas y GPS sin bloquear UI
    _loadQuestionsAndAnswers();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 2),
        onTimeout: () => LocationPermission.denied,
      );
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 2),
          onTimeout: () => LocationPermission.denied,
        );
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(
          const Duration(seconds: 3),
        );
        if (mounted) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
            _gpsAccuracy = position.accuracy;
            _initialGpsLocation ??= LatLng(position.latitude, position.longitude);
            _isRuralZone = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Ubicación por defecto establecida: $e');
    }
  }

  Future<void> _loadQuestionsAndAnswers() async {
    try {
      final dbHelper = DatabaseHelper();
      
      final localQuestions = await dbHelper.getQuestions(widget.survey.id).timeout(
        const Duration(seconds: 2),
        onTimeout: () => [],
      );

      List<QuestionModel> loaded = [];
      if (localQuestions.isNotEmpty) {
        loaded = localQuestions.map((q) => QuestionModel.fromSurveyQuestionModel(q)).toList();
      } else {
        loaded = List<QuestionModel>.from(widget.survey.questions);
      }

      if (_currentResponseSetId != null) {
        final savedResponses = await dbHelper.getResponsesBySetId(_currentResponseSetId!).timeout(
          const Duration(seconds: 2),
          onTimeout: () => [],
        );
        for (var resp in savedResponses) {
          final qId = int.tryParse(resp['id_pregunta'].toString());
          final matched = loaded.where((q) => q.id == qId);
          if (matched.isNotEmpty) {
            matched.first.answer = resp['c_respuesta'] ?? resp['glgis'];
          }
          if (resp['status'] != null) {
            _currentStatus = resp['status'];
          }
        }
      }

      final sections = <String>{};
      for (var q in loaded) {
        if (q.section != null && q.section!.isNotEmpty) {
          sections.add(q.section!);
        }
      }

      if (mounted) {
        setState(() {
          if (loaded.isNotEmpty) {
            _questions = loaded;
          }
          _availableSections = sections.toList();
          if (_availableSections.isNotEmpty && _selectedSection == null) {
            _selectedSection = _availableSections.first;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error enriqueciendo preguntas: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper: guarda bytes en carpeta privada 'uploads'
  Future<Map<String, String>> _saveBytesToUploads(
    Uint8List bytes,
    String baseName,
    String extension,
  ) async {
    final dbPath = await getDatabasesPath();
    final uploadsDir = Directory('$dbPath/uploads');
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    final fileName = '$baseName$extension';
    final filePath = '${uploadsDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return {'path': filePath, 'name': fileName, 'ext': extension};
  }

  // Evaluación de Skip Logic (Lógica condicional)
  bool _isQuestionVisible(QuestionModel q) {
    if (q.dependsOnField == null || q.dependsOnField!.trim().isEmpty) return true;

    final depField = q.dependsOnField!.trim();
    final parent = _questions.firstWhere(
      (item) => item.field == depField || item.id.toString() == depField,
      orElse: () => QuestionModel(id: -1, text: '', type: '', options: []),
    );

    if (parent.id == -1 || parent.answer == null || parent.answer!.trim().isEmpty) {
      return false;
    }

    if (q.dependsOnValue != null) {
      final expected = q.dependsOnValue.toString().trim().toLowerCase();
      final actual = parent.answer.toString().trim().toLowerCase();
      return actual == expected;
    }

    return true;
  }

  // Validación de campo
  String? _validateQuestion(QuestionModel q) {
    if (!_isQuestionVisible(q)) return null;

    if (q.isRequired && (q.answer == null || q.answer!.trim().isEmpty)) {
      return 'Este campo es obligatorio';
    }

    if (q.minValue != null || q.maxValue != null) {
      final numVal = double.tryParse(q.answer ?? '');
      if (numVal != null) {
        if (q.minValue != null && numVal < q.minValue!) {
          return 'El valor mínimo permitido es ${q.minValue}';
        }
        if (q.maxValue != null && numVal > q.maxValue!) {
          return 'El valor máximo permitido es ${q.maxValue}';
        }
      }
    }

    if (q.regexPattern != null && q.answer != null && q.answer!.isNotEmpty) {
      final regExp = RegExp(q.regexPattern!);
      if (!regExp.hasMatch(q.answer!)) {
        return 'El formato ingresado no es válido';
      }
    }

    // Reglas de validación estrictas (DNI, RUC, Celular)
    if (q.answer != null && q.answer!.trim().isNotEmpty) {
      final val = q.answer!.trim();
      final lowerField = q.field.toLowerCase();
      final lowerText = q.text.toLowerCase();

      // DNI: Exactamente 8 dígitos numéricos
      if (lowerField.contains('dni') || lowerText.contains('dni')) {
        if (!RegExp(r'^\d{8}$').hasMatch(val)) {
          return 'El DNI debe contener exactamente 8 dígitos numéricos';
        }
      }

      // RUC: Exactamente 11 dígitos numéricos
      if (lowerField.contains('ruc') || lowerText.contains('ruc')) {
        if (!RegExp(r'^\d{11}$').hasMatch(val)) {
          return 'El RUC debe contener exactamente 11 dígitos numéricos';
        }
      }

      // Celular / Teléfono: Exactamente 9 dígitos
      if (lowerField.contains('celular') || lowerField.contains('telefono') ||
          lowerText.contains('celular') || lowerText.contains('teléfono') || lowerText.contains('telefono')) {
        if (!RegExp(r'^\d{9}$').hasMatch(val)) {
          return 'El número de celular debe contener 9 dígitos';
        }
      }
    }

    return null;
  }

  Future<void> _handleSave({required bool isDraft}) async {
    _validationErrors.clear();

    // Si vamos a finalizar (no borrador), validamos campos obligatorios
    if (!isDraft) {
      bool hasErrors = false;
      for (final question in _questions) {
        if (_isQuestionVisible(question)) {
          final err = _validateQuestion(question);
          if (err != null) {
            _validationErrors[question.id] = err;
            hasErrors = true;
          }
        }
      }

      if (hasErrors) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor completa todos los campos obligatorios antes de finalizar'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final dbHelper = DatabaseHelper();
      final String responseSetId = _currentResponseSetId ??
          'set_${DateTime.now().millisecondsSinceEpoch}';
      final String newStatus = isDraft ? 'DRAFT' : 'COMPLETED';

      // Si ya existían respuestas previas de este set, las eliminamos para reinsertar actualizadas
      await dbHelper.deleteResponseSet(responseSetId);

      for (final question in _questions) {
        // Si no es visible por skip logic, no guardamos respuesta
        if (!_isQuestionVisible(question)) continue;

        Map<String, dynamic> responseData = {
          'id_encuesta': widget.survey.id.toString(),
          'id_pregunta': question.id.toString(),
          'c_tipo_pregunta': question.type,
          'c_respuesta': null,
          'c_nombre_file': null,
          'c_extension': null,
          'glgis': null,
          'response_set_id': responseSetId,
          'status': newStatus,
        };

        final qType = question.type.toUpperCase();

        switch (qType) {
          case 'PHOTO':
          case 'SIGNATURE':
          case 'FILE':
            if (question.answer != null && question.answer!.isNotEmpty) {
              if (question.answer!.startsWith('data:image') ||
                  question.answer!.length > 500) {
                // Es Base64 en memoria -> guardar archivo
                try {
                  final raw = question.answer!.contains(',')
                      ? question.answer!.split(',')[1]
                      : question.answer!;
                  final bytes = base64Decode(raw);
                  final ext = qType == 'SIGNATURE' ? '.png' : '.jpg';
                  final saved = await _saveBytesToUploads(
                    bytes,
                    'file_${question.id}_${DateTime.now().millisecondsSinceEpoch}',
                    ext,
                  );
                  responseData['c_respuesta'] = saved['path'];
                  responseData['c_nombre_file'] = saved['name'];
                  responseData['c_extension'] = saved['ext'];
                } catch (_) {
                  responseData['c_respuesta'] = question.answer;
                }
              } else {
                responseData['c_respuesta'] = question.answer;
              }
            }
            break;

          case 'MAP':
          case 'GEOMETRY':
          case 'POLYGON':
          case 'LINE':
          case 'GEOSHAPE':
          case 'GEOTRACE':
          case 'GEOPOINT':
          case 'POINT':
            if (question.answer != null && question.answer!.isNotEmpty) {
              final parsed = GisCalculator.fromGeoJsonOrString(question.answer);
              if (parsed != null) {
                final geoJsonMap = GisCalculator.toGeoJson(parsed.type, parsed.points);
                responseData['glgis'] = jsonEncode(geoJsonMap);
              } else {
                responseData['glgis'] = question.answer;
              }
              responseData['c_respuesta'] = question.answer;
            }
            break;

          case 'COORDINATE':
            if (question.answer != null && question.answer!.isNotEmpty) {
              final parsed = GisCalculator.fromGeoJsonOrString(question.answer);
              if (parsed != null) {
                final geoJsonMap = GisCalculator.toGeoJson(parsed.type, parsed.points);
                responseData['glgis'] = jsonEncode(geoJsonMap);
              } else {
                responseData['glgis'] = question.answer;
              }
              responseData['c_respuesta'] = question.answer;
            } else {
              final geoJson = {
                "type": "Point",
                "coordinates": [
                  _currentLocation.longitude,
                  _currentLocation.latitude
                ]
              };
              responseData['glgis'] = jsonEncode(geoJson);
              responseData['c_respuesta'] = '${_currentLocation.latitude}, ${_currentLocation.longitude}';
            }
            break;

          default:
            responseData['c_respuesta'] = question.answer;
            break;
        }

        await dbHelper.insertResponse(responseData);
      }

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDraft
                ? '💾 Borrador guardado exitosamente'
                : '✅ Encuesta completada y lista para sincronizar'),
            backgroundColor: isDraft ? Colors.orange.shade800 : Colors.green.shade800,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error guardando respuestas: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.survey.title),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Asistente de Dictado por Voz IA
          IconButton(
            icon: const Icon(Icons.mic, color: Colors.white),
            tooltip: 'Dictado Asistido por IA',
            onPressed: _showVoiceAssistantDialog,
          ),
          // Botón Guardar Borrador
          TextButton.icon(
            icon: const Icon(Icons.save_outlined, color: Colors.white, size: 20),
            label: const Text('Borrador', style: TextStyle(color: Colors.white)),
            onPressed: () => _handleSave(isDraft: true),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Selector de Secciones si existen
                if (_availableSections.isNotEmpty) _buildSectionTabs(),

                // Banner de ubicación GPS
                if (_isRuralZone)
                  Container(
                    width: double.infinity,
                    color: Colors.green.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.satellite_alt, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'GPS: ${_currentLocation.latitude.toStringAsFixed(5)}, ${_currentLocation.longitude.toStringAsFixed(5)}',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Lista de Preguntas
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      final question = _questions[index];
                      // Si hay secciones y la pregunta no pertenece a la sección activa, no mostrar
                      if (_selectedSection != null &&
                          question.section != null &&
                          question.section!.isNotEmpty &&
                          question.section != _selectedSection) {
                        return const SizedBox.shrink();
                      }
                      return _buildQuestionCard(question, index);
                    },
                  ),
                ),

                // Barra Inferior de Acción
                _buildBottomActionBar(),
              ],
            ),
    );
  }

  Widget _buildSectionTabs() {
    return Container(
      height: 48,
      color: Colors.grey.shade100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _availableSections.length,
        itemBuilder: (context, idx) {
          final sec = _availableSections[idx];
          final isSelected = sec == _selectedSection;
          return GestureDetector(
            onTap: () => setState(() => _selectedSection = sec),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? AppColors.primaryColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                sec,
                style: TextStyle(
                  color: isSelected ? AppColors.primaryColor : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionCard(QuestionModel question, int index) {
    if (question.type.toUpperCase() == "COORDINATE" || !_isQuestionVisible(question)) {
      return const SizedBox.shrink();
    }

    final hasError = _validationErrors.containsKey(question.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasError
            ? const BorderSide(color: Colors.red, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              question.text,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (question.isRequired)
                            const Text(' *', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (question.hint != null && question.hint!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            question.hint!,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 40),
                child: Text(
                  _validationErrors[question.id]!,
                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 12),
            _buildInputForQuestion(question),
          ],
        ),
      ),
    );
  }

  Widget _buildInputForQuestion(QuestionModel question) {
    final type = question.type.toUpperCase();
    switch (type) {
      case 'SELECTIONSIMPLE':
      case 'SELECT_ONE':
      case 'CHOICE':
        return _buildRadioButtons(question);
      case 'SELECTIONMULTIPLE':
      case 'SELECT_MULTIPLE':
      case 'MULTIPLE':
        return _buildCheckboxes(question);
      case 'DATE':
      case 'DATETIME':
      case 'TIME':
        return _buildDateTimeInput(question);
      case 'NUMBER':
      case 'INTEGER':
      case 'DECIMAL':
        return _buildNumberInput(question);
      case 'EMAIL':
        return _buildEmailInput(question);
      case 'SIGNATURE':
        return _buildSignatureInput(question);
      case 'MAP':
      case 'GEOMETRY':
      case 'POLYGON':
      case 'LINE':
      case 'GEOSHAPE':
      case 'GEOTRACE':
      case 'GEOPOINT':
      case 'POINT':
      case 'GPS':
        return _buildMapButton(question);
      case 'FILE':
        return _buildFileInput(question);
      case 'PHOTO':
      case 'IMAGE':
        return _buildPhotoInput(question);
      case 'TEXT':
      default:
        return _buildDefaultTextInput(question);
    }
  }

  Widget _buildRadioButtons(QuestionModel question) {
    if (question.options.isEmpty) {
      return _buildDefaultTextInput(question);
    }

    // Si tiene 4 o menos opciones, mostrar tarjetas de selección directa
    if (question.options.length <= 4) {
      return Column(
        children: question.options.map((option) {
          final isSelected = question.answer == option.text || question.answer == option.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  question.answer = option.text;
                  _validationErrors.remove(question.id);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryColor.withValues(alpha: 0.08) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryColor : Colors.grey.shade300,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? AppColors.primaryColor : Colors.grey.shade500,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppColors.primaryColor : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    // Si tiene más de 4 opciones, selector desplegable moderno con modal de búsqueda
    final String currentLabel = question.options.firstWhere(
      (o) => o.text == question.answer || o.value == question.answer,
      orElse: () => OptionModel(id: 0, text: question.answer ?? ''),
    ).text;
    final bool hasSelection = currentLabel.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showSearchableOptionPicker(question),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hasSelection ? AppColors.primaryColor.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasSelection ? AppColors.primaryColor.withValues(alpha: 0.6) : Colors.grey.shade400,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasSelection ? currentLabel : (question.hint ?? 'Seleccione una opción...'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
                  color: hasSelection ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down_circle_outlined, color: AppColors.primaryColor, size: 22),
          ],
        ),
      ),
    );
  }

  void _showSearchableOptionPicker(QuestionModel question) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = question.options
                .where((o) => o.text.toLowerCase().contains(filter.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    question.text,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar opción...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.primaryColor),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        filter = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final opt = filtered[idx];
                        final isSel = question.answer == opt.text || question.answer == opt.value;
                        return ListTile(
                          title: Text(
                            opt.text,
                            style: TextStyle(
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              color: isSel ? AppColors.primaryColor : Colors.black87,
                            ),
                          ),
                          trailing: isSel ? const Icon(Icons.check_circle, color: AppColors.primaryColor) : null,
                          onTap: () {
                            setState(() {
                              question.answer = opt.text;
                              _validationErrors.remove(question.id);
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCheckboxes(QuestionModel question) {
    List<String> selected = question.answer != null && question.answer!.isNotEmpty
        ? question.answer!.split(', ')
        : [];

    return Column(
      children: question.options.map((option) {
        final isChecked = selected.contains(option.text);
        return CheckboxListTile(
          title: Text(option.text),
          value: isChecked,
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                selected.add(option.text);
              } else {
                selected.remove(option.text);
              }
              question.answer = selected.join(', ');
              _validationErrors.remove(question.id);
            });
          },
          activeColor: AppColors.primaryColor,
        );
      }).toList(),
    );
  }

  Widget _buildDefaultTextInput(QuestionModel question) {
    return TextFormField(
      initialValue: question.answer,
      decoration: InputDecoration(
        hintText: question.hint ?? 'Escribe tu respuesta aquí',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (value) {
        question.answer = value;
        _validationErrors.remove(question.id);
      },
    );
  }

  Widget _buildNumberInput(QuestionModel question) {
    return TextFormField(
      initialValue: question.answer,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: question.hint ?? 'Ingrese un número',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (value) {
        question.answer = value;
        _validationErrors.remove(question.id);
      },
    );
  }

  Widget _buildEmailInput(QuestionModel question) {
    return TextFormField(
      initialValue: question.answer,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        hintText: question.hint ?? 'correo@ejemplo.com',
        prefixIcon: const Icon(Icons.email_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (value) {
        question.answer = value;
        _validationErrors.remove(question.id);
      },
    );
  }

  Widget _buildDateTimeInput(QuestionModel question) {
    final bool hasDate = question.answer != null && question.answer!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: hasDate ? AppColors.primaryColor.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDate ? AppColors.primaryColor.withValues(alpha: 0.4) : Colors.grey.shade300,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasDate ? AppColors.primaryColor : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.calendar_month,
              color: hasDate ? Colors.white : Colors.grey.shade700,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasDate ? 'Fecha Seleccionada' : 'Seleccionar Fecha',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hasDate ? AppColors.primaryColor : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDate ? question.answer! : 'DD/MM/AAAA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: hasDate ? Colors.black87 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.today, size: 18),
            label: Text(hasDate ? 'Cambiar' : 'Elegir Fecha'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              DateTime initial = DateTime.now();
              if (hasDate) {
                final parsed = DateTime.tryParse(question.answer!);
                if (parsed != null) initial = parsed;
              }
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(1970),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppColors.primaryColor,
                        onPrimary: Colors.white,
                        onSurface: Colors.black87,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  final formatted =
                      "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                  question.answer = formatted;
                  _validationErrors.remove(question.id);
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton(QuestionModel question) {
    final qType = question.type.toUpperCase();
    final bool isPoint = qType == 'POINT' || qType == 'GEOPOINT' || qType == 'GPS' || qType == 'MAP';

    Widget previewWidget = const SizedBox.shrink();

    if (question.answer != null && question.answer!.isNotEmpty) {
      final parsed = GisCalculator.fromGeoJsonOrString(question.answer);
      if (parsed != null) {
        IconData icon = Icons.place;
        String title = 'Punto seleccionado';
        String subtitle = '';

        switch (parsed.type) {
          case GeoGeometryType.point:
            icon = Icons.gps_fixed;
            title = 'Punto GPS Georreferenciado';
            final p = parsed.points.first;
            subtitle = 'Lat: ${p.latitude.toStringAsFixed(6)} | Lng: ${p.longitude.toStringAsFixed(6)}';
            break;
          case GeoGeometryType.line:
            icon = Icons.timeline;
            title = 'Línea / Ruta (${parsed.points.length} puntos)';
            subtitle = 'Distancia: ${GisCalculator.formatDistance(GisCalculator.calculateDistance(parsed.points))}';
            break;
          case GeoGeometryType.polygon:
            icon = Icons.crop_square;
            title = 'Polígono / Área (${parsed.points.length} vértices)';
            final areaStr = GisCalculator.formatArea(GisCalculator.calculatePolygonArea(parsed.points));
            final perimStr = GisCalculator.formatDistance(GisCalculator.calculatePerimeter(parsed.points));
            subtitle = 'Área: $areaStr | Perímetro: $perimStr';
            break;
        }

        previewWidget = Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border.all(color: Colors.green.shade400, width: 1.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Borrar ubicación',
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                onPressed: () {
                  setState(() {
                    question.answer = null;
                  });
                },
              ),
            ],
          ),
        );
      }
    }

    GeoGeometryType defaultType = isPoint
        ? GeoGeometryType.point
        : (qType == 'POLYGON' || qType == 'GEOSHAPE' ? GeoGeometryType.polygon : GeoGeometryType.line);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        previewWidget,
        Row(
          children: [
            if (isPoint) ...[
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Obtener Mi GPS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('📡 Capturando coordenadas GPS satelitales...'), duration: Duration(seconds: 1)),
                      );
                      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
                          .timeout(const Duration(seconds: 5));
                      final geoJson = jsonEncode({
                        "type": "Point",
                        "coordinates": [pos.longitude, pos.latitude]
                      });
                      setState(() {
                        question.answer = geoJson;
                        _validationErrors.remove(question.id);
                      });
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al capturar GPS: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.map, size: 18),
                label: Text(isPoint ? 'Ajustar en Mapa' : (question.answer == null ? 'Dibujar en Mapa' : 'Editar en Mapa')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  side: const BorderSide(color: AppColors.primaryColor, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapInputPage(
                        initialValue: question.answer,
                        questionText: question.text,
                        defaultGeometryType: defaultType,
                        allowGpsOnly: question.allowGpsOnly,
                      ),
                    ),
                  );

                  if (result != null) {
                    setState(() {
                      question.answer = result;
                      _validationErrors.remove(question.id);
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoInput(QuestionModel question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.answer != null && question.answer!.isNotEmpty) ...[
          Container(
            height: 160,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: question.answer!.startsWith('data:image')
                  ? Image.memory(
                      base64Decode(question.answer!.split(',').last),
                      fit: BoxFit.cover,
                    )
                  : Image.file(File(question.answer!), fit: BoxFit.cover),
            ),
          ),
          // Botón de Autocompletado IA Multimodal Gemini
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
              label: const Text('✨ Autocompletar con IA (Gemini)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
              onPressed: () => _analyzePhotoWithAI(question),
            ),
          ),
        ],
        Row(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Cámara'),
              onPressed: () => _pickOptimizedImage(question, ImageSource.camera),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Galería'),
              onPressed: () => _pickOptimizedImage(question, ImageSource.gallery),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickOptimizedImage(QuestionModel question, ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      HapticFeedback.mediumImpact();

      // Incrustar marca de agua geoespacial y antifraude de manera asíncrona
      final stampedPath = await WatermarkService.stampMetadataOnImage(
        imagePath: pickedFile.path,
        latitude: _currentLocation.latitude,
        longitude: _currentLocation.longitude,
        accuracy: _gpsAccuracy > 0 ? _gpsAccuracy : null,
        timestamp: DateTime.now(),
        title: question.text,
      );

      setState(() {
        question.answer = stampedPath;
        _validationErrors.remove(question.id);
      });
    }
  }

  // ==========================================
  // IA MULTIMODAL & ASISTENTE DE VOZ (GEMINI)
  // ==========================================

  Future<void> _analyzePhotoWithAI(QuestionModel photoQuestion) async {
    if (photoQuestion.answer == null || photoQuestion.answer!.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  '🤖 Analizando predio y fachada con Gemini IA Multimodal...',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      String imageBase64;
      if (photoQuestion.answer!.startsWith('data:image')) {
        imageBase64 = photoQuestion.answer!.split(',').last;
      } else {
        final file = File(photoQuestion.answer!);
        if (!await file.exists()) {
          throw Exception('No se encuentra el archivo de imagen capturado');
        }
        final bytes = await file.readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      final url = Uri.parse('https://glgisclienteb.ideasg.org/surveygo/api/ai/analyze-facade');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          'mimeType': 'image/jpeg',
        }),
      ).timeout(const Duration(seconds: 25));

      if (mounted) Navigator.pop(context); // Cerrar diálogo de carga

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['success'] == true && data['analysis'] != null) {
          final analysis = data['analysis'] as Map<String, dynamic>;
          _showAiAnalysisResultsModal(analysis);
        } else {
          throw Exception(data['error'] ?? 'Respuesta de IA sin análisis');
        }
      } else {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst || route.settings.name != null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en análisis de IA: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _showAiAnalysisResultsModal(Map<String, dynamic> analysis) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('✨ Autocompletado IA Gemini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Atributos prediales detectados en la fachada', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildAiItem('🏢 Pisos Estimados', '${analysis['num_pisos'] ?? "No detectado"}'),
                    _buildAiItem('🧱 Material Predominante', '${analysis['material_predominante'] ?? "No detectado"}'),
                    _buildAiItem('🏷️ Estado de Conservación', '${analysis['estado_conservacion'] ?? "No detectado"}'),
                    _buildAiItem('🏠 Uso Aparente', '${analysis['uso_aparente'] ?? "No detectado"}'),
                    if (analysis['num_medidor'] != null)
                      _buildAiItem('⚡ Medidor Visible', '${analysis['num_medidor']} (${analysis['suministro_tipo'] ?? "Luz"})'),
                    if (analysis['fachada_color'] != null)
                      _buildAiItem('🎨 Color de Fachada', '${analysis['fachada_color']}'),
                    if (analysis['observacion_tecnica'] != null)
                      _buildAiItem('📝 Resumen Técnico', '${analysis['observacion_tecnica']}'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('✅ Aplicar Automáticamente al Formulario'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  _applyAiAnalysisToQuestions(analysis);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✨ ¡Campos autocompletados exitosamente por la IA!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))),
          Expanded(flex: 5, child: Text(value, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800))),
        ],
      ),
    );
  }

  void _applyAiAnalysisToQuestions(Map<String, dynamic> analysis) {
    setState(() {
      for (final q in _questions) {
        final text = q.text.toLowerCase();
        final field = q.field.toLowerCase();

        // Pisos
        if (text.contains('piso') || text.contains('nivel') || field.contains('piso')) {
          if (analysis['num_pisos'] != null) {
            q.answer = analysis['num_pisos'].toString();
          }
        }
        // Material
        else if (text.contains('material') || text.contains('muro') || field.contains('material')) {
          if (analysis['material_predominante'] != null) {
            final mat = analysis['material_predominante'].toString();
            if (q.options.isNotEmpty) {
              final matched = q.options.firstWhere(
                (o) => mat.toLowerCase().contains(o.text.toLowerCase()) || o.text.toLowerCase().contains(mat.toLowerCase()),
                orElse: () => q.options.first,
              );
              q.answer = matched.text;
            } else {
              q.answer = mat;
            }
          }
        }
        // Estado
        else if (text.contains('estado') || text.contains('conservac') || field.contains('estado')) {
          if (analysis['estado_conservacion'] != null) {
            final est = analysis['estado_conservacion'].toString();
            if (q.options.isNotEmpty) {
              final matched = q.options.firstWhere(
                (o) => est.toLowerCase().contains(o.text.toLowerCase()) || o.text.toLowerCase().contains(est.toLowerCase()),
                orElse: () => q.options.first,
              );
              q.answer = matched.text;
            } else {
              q.answer = est;
            }
          }
        }
        // Uso
        else if (text.contains('uso') || text.contains('destino') || field.contains('uso')) {
          if (analysis['uso_aparente'] != null) {
            final uso = analysis['uso_aparente'].toString();
            if (q.options.isNotEmpty) {
              final matched = q.options.firstWhere(
                (o) => uso.toLowerCase().contains(o.text.toLowerCase()) || o.text.toLowerCase().contains(uso.toLowerCase()),
                orElse: () => q.options.first,
              );
              q.answer = matched.text;
            } else {
              q.answer = uso;
            }
          }
        }
        // Medidor
        else if (text.contains('medidor') || text.contains('suministro') || field.contains('medidor')) {
          if (analysis['num_medidor'] != null) {
            q.answer = analysis['num_medidor'].toString();
          }
        }
        // Color
        else if (text.contains('color') || field.contains('color')) {
          if (analysis['fachada_color'] != null) {
            q.answer = analysis['fachada_color'].toString();
          }
        }
        // Observación
        else if (text.contains('observac') || field.contains('observac')) {
          if (analysis['observacion_tecnica'] != null) {
            q.answer = analysis['observacion_tecnica'].toString();
          }
        }
        _validationErrors.remove(q.id);
      }
    });
  }

  void _showVoiceAssistantDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mic, color: Colors.blue, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text('Dictado Asistido por IA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Dicta o escribe notas sobre el predio (pisos, materiales, uso, medidor). Gemini estructurará automáticamente el formulario.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ej: Casa de 2 pisos, ladrillo bueno, uso vivienda y tienda, medidor 89123...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  if (isSubmitting) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Procesando dictado con Gemini 3.5 Flash...', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Estructurar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting ? null : () async {
                    final note = textCtrl.text.trim();
                    if (note.isEmpty) return;

                    setDialogState(() => isSubmitting = true);
                    try {
                      final url = Uri.parse('https://glgisclienteb.ideasg.org/surveygo/api/ai/parse-voice');
                      final questionsSummary = _questions.map((q) => {
                        'id': q.id,
                        'fieldName': q.field,
                        'questionText': q.text,
                        'questionType': q.type,
                        'options': q.options.map((o) => o.text).toList(),
                      }).toList();

                      final resp = await http.post(
                        url,
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'text': note,
                          'questions': questionsSummary,
                        }),
                      ).timeout(const Duration(seconds: 20));

                      if (resp.statusCode == 200) {
                        final resJson = jsonDecode(resp.body);
                        if (resJson['success'] == true && resJson['data'] != null) {
                          final answers = resJson['data']['answers'] as Map<String, dynamic>?;
                          if (answers != null && answers.isNotEmpty) {
                            setState(() {
                              for (final entry in answers.entries) {
                                final key = entry.key.toString().toLowerCase();
                                final val = entry.value.toString();
                                for (final q in _questions) {
                                  if (q.id.toString() == key ||
                                      q.field.toLowerCase() == key ||
                                      q.text.toLowerCase().contains(key)) {
                                    q.answer = val;
                                    _validationErrors.remove(q.id);
                                  }
                                }
                              }
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✨ Dictado procesado: ${resJson['data']['summary'] ?? 'Formulario actualizado'}'),
                                backgroundColor: Colors.green.shade800,
                              ),
                            );
                          }
                        }
                      }
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error procesando audio/texto: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSignatureInput(QuestionModel question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.answer != null && question.answer!.isNotEmpty) ...[
          Container(
            height: 120,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: question.answer!.startsWith('data:image')
                ? Image.memory(base64Decode(question.answer!.split(',').last))
                : Image.file(File(question.answer!)),
          ),
        ],
        ElevatedButton.icon(
          icon: const Icon(Icons.draw),
          label: Text(question.answer == null || question.answer!.isEmpty
              ? 'Firmar Digitalmente'
              : 'Modificar Firma'),
          onPressed: () => _openSignatureDialog(question),
        ),
      ],
    );
  }

  void _openSignatureDialog(QuestionModel question) {
    final SignatureController sigController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Firma Digital'),
          content: SizedBox(
            width: 320,
            height: 220,
            child: Signature(
              controller: sigController,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => sigController.clear(),
              child: const Text('Limpiar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (sigController.isNotEmpty) {
                  final bytes = await sigController.toPngBytes();
                  if (bytes != null) {
                    setState(() {
                      question.answer = 'data:image/png;base64,${base64Encode(bytes)}';
                      _validationErrors.remove(question.id);
                    });
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar Firma'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFileInput(QuestionModel question) {
    return Row(
      children: [
        Expanded(
          child: Text(
            question.answer == null || question.answer!.isEmpty
                ? 'Ningún archivo seleccionado'
                : 'Archivo: ${question.answer!.split('/').last}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.attach_file),
          label: const Text('Adjuntar'),
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles();
            if (result != null && result.files.single.path != null) {
              setState(() {
                question.answer = result.files.single.path;
                _validationErrors.remove(question.id);
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar Borrador'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _handleSave(isDraft: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finalizar Encuesta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _handleSave(isDraft: false),
            ),
          ),
        ],
      ),
    );
  }
}