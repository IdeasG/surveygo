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
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';
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
            if (question.answer != null && question.answer!.isNotEmpty) {
              final parsed = GisCalculator.fromGeoJsonOrString(question.answer);
              if (parsed != null) {
                final geoJsonMap = GisCalculator.toGeoJson(parsed.type, parsed.points);
                responseData['glgis'] = jsonEncode(geoJsonMap);
              } else {
                responseData['glgis'] = question.answer;
              }
              responseData['c_respuesta'] = null;
            }
            break;

          case 'COORDINATE':
            final geoJson = {
              "type": "Point",
              "coordinates": [
                _currentLocation.longitude,
                _currentLocation.latitude
              ]
            };
            responseData['glgis'] = jsonEncode(geoJson);
            responseData['c_respuesta'] = null;
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
        return _buildRadioButtons(question);
      case 'SELECTIONMULTIPLE':
        return _buildCheckboxes(question);
      case 'DATETIME':
        return _buildDateTimeInput(question);
      case 'NUMBER':
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
        return _buildMapButton(question);
      case 'FILE':
        return _buildFileInput(question);
      case 'PHOTO':
        return _buildPhotoInput(question);
      case 'TEXT':
      default:
        return _buildDefaultTextInput(question);
    }
  }

  Widget _buildRadioButtons(QuestionModel question) {
    return Column(
      children: question.options.map((option) {
        return RadioListTile<String>(
          title: Text(option.text),
          value: option.text,
          groupValue: question.answer,
          onChanged: (value) {
            setState(() {
              question.answer = value;
              _validationErrors.remove(question.id);
            });
          },
          activeColor: AppColors.primaryColor,
        );
      }).toList(),
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
    return Row(
      children: [
        Expanded(
          child: Text(
            question.answer == null || question.answer!.isEmpty
                ? 'Ninguna fecha seleccionada'
                : 'Fecha: ${question.answer}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.calendar_today),
          label: const Text('Elegir Fecha'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() {
                question.answer = picked.toIso8601String().split('T')[0];
                _validationErrors.remove(question.id);
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildMapButton(QuestionModel question) {
    Widget previewWidget = const SizedBox.shrink();

    if (question.answer != null && question.answer!.isNotEmpty) {
      final parsed = GisCalculator.fromGeoJsonOrString(question.answer);
      if (parsed != null) {
        IconData icon = Icons.place;
        String title = 'Punto seleccionado';
        String subtitle = '';

        switch (parsed.type) {
          case GeoGeometryType.point:
            icon = Icons.place;
            title = 'Punto Georreferenciado';
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
            subtitle = 'Área: $areaStr\nPerímetro: $perimStr';
            break;
        }

        previewWidget = Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: 0.06),
            border: Border.all(color: AppColors.primaryColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryColor, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryColor),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    }

    GeoGeometryType defaultType = GeoGeometryType.point;
    final qType = question.type.toUpperCase();
    if (qType == 'POLYGON' || qType == 'GEOSHAPE') {
      defaultType = GeoGeometryType.polygon;
    } else if (qType == 'LINE' || qType == 'GEOTRACE') {
      defaultType = GeoGeometryType.line;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        previewWidget,
        ElevatedButton.icon(
          icon: const Icon(Icons.map),
          label: Text(question.answer == null || question.answer!.isEmpty
              ? 'Capturar en Mapa (Punto/Línea/Polígono)'
              : 'Editar Geometría en Mapa'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
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
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        question.answer = pickedFile.path;
        _validationErrors.remove(question.id);
      });
    }
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
                Navigator.pop(ctx);
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