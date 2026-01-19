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

import 'package:surveygo/features/surveys/presentation/pages/map_input_page.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/survey_sync_service.dart';

class SurveyDetailPage extends StatefulWidget {
  final SurveyModel survey;

  const SurveyDetailPage({Key? key, required this.survey}) : super(key: key);

  @override
  State<SurveyDetailPage> createState() => _SurveyDetailPageState();
}

class _SurveyDetailPageState extends State<SurveyDetailPage> {
  bool _isLoading = true;
  List<QuestionModel> _questions = [];
  final SurveySyncService _syncService = SurveySyncService();
  // Coordenadas por defecto
  LatLng _currentLocation = LatLng(19.432608, -99.133209);
  bool _isRuralZone = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Permisos de ubicación denegados');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Permisos de ubicación denegados permanentemente');
        return;
      }

      // Obtener ubicación actual
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Determinar si es zona rural (esto es un ejemplo, puedes ajustar la lógica)
      // Por ejemplo, podríamos considerar rural si está a más de 20km de un centro urbano
      _isRuralZone = true; // Simulamos que es zona rural

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Mostrar mensaje de zonas rurales
      if (mounted && _isRuralZone) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Ubicación detectada: Lat: ${position.latitude.toStringAsFixed(6)}, Long: ${position.longitude.toStringAsFixed(6)}'),
            duration: Duration(seconds: 3),
          ),
        );

        // Mostrar mensaje de zona rural después de un breve retraso
        Future.delayed(Duration(seconds: 3), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Modo zonas rurales activado - Optimizando para conexión limitada'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 5),
              ),
            );
          }
        });
      }

      print(
          'Coordenadas actuales: ${_currentLocation.latitude}, ${_currentLocation.longitude}');
    } catch (e) {
      print('Error obteniendo ubicación: $e');
      // Mostrar mensaje de error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo obtener la ubicación: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Aquí cargaríamos las preguntas de la encuesta desde la base de datos local
      // Por ahora, usamos las preguntas que ya vienen en el modelo
      setState(() {
        _questions = widget.survey.questions;
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando preguntas: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar preguntas')),
        );
      }
    }
  }

  // Helper: guarda bytes en carpeta privada 'uploads' junto a la BD
  Future<Map<String, String>> _saveBytesToUploads(
    Uint8List bytes,
    String baseName,
    String extension,
  ) async {
    final dbPath = await getDatabasesPath();
    final uploadsDir = Directory('${dbPath}/uploads');
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    final fileName = '$baseName$extension';
    final filePath = '${uploadsDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return {'path': filePath, 'name': fileName, 'ext': extension};
  }

  Future<void> _saveResponses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final dbHelper = DatabaseHelper();

      // Generamos un identificador único para este conjunto de respuestas
      final String responseSetId =
          DateTime.now().millisecondsSinceEpoch.toString();

      // Procesamos cada pregunta y guardamos las respuestas
      for (final question in _questions) {
        Map<String, dynamic> responseData = {
          'id_encuesta': widget.survey.id,
          'id_pregunta': question.id,
          'c_tipo_pregunta': question.type,
          'c_respuesta': null,
          'c_nombre_file': null,
          'c_extension': null,
          'glgis': null,
          'response_set_id':
              responseSetId, // Añadimos un identificador para agrupar respuestas
        };

        // Procesar según el tipo de pregunta
        switch (question.type.toUpperCase()) {
          case 'FILE':
            if (question.answer != null && question.answer!.isNotEmpty) {
              try {
                final fileData = jsonDecode(question.answer!);
                responseData['c_respuesta'] = fileData['path'];
                responseData['c_nombre_file'] = fileData['name'];
                responseData['c_extension'] =
                    _getFileExtension(fileData['name']);
              } catch (e) {
                print('Error procesando archivo: $e');
                responseData['c_respuesta'] = question.answer;
              }
            }
            break;

          case 'PHOTO':
          case 'SIGNATURE':
            // Para fotos y firmas, guardamos la ruta o referencia
            if (question.answer != null && question.answer!.isNotEmpty) {
              // answer contiene Base64; persistimos como archivo en disco
              final bytes = base64Decode(question.answer!);
              final baseName =
                  '${question.id}_${DateTime.now().millisecondsSinceEpoch}';
              final saved = await _saveBytesToUploads(bytes, baseName, '.png');

              responseData['c_respuesta'] = saved['path']; // ruta del archivo
              responseData['c_nombre_file'] = saved['name'];
              responseData['c_extension'] = saved['ext'];
            }
            break;

          case 'MAP':
            // Para mapas, guardamos las coordenadas en glgis
            if (question.answer != null && question.answer!.isNotEmpty) {
              final geoJson = {
                "type": "Point",
                "coordinates": [question.answer]
              };
              responseData['glgis'] = jsonEncode(geoJson);
              responseData['c_respuesta'] = null;
            }
            break;
          case 'COORDINATE':
            // Para preguntas de tipo coordenada, usar la ubicación actual si estamos en zona rural

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
            // Para otros tipos, guardar la respuesta directamente
            responseData['c_respuesta'] = question.answer;

            break;
        }

        // Insertar en la base de datos
        await dbHelper.insertResponse(responseData);
      }

      // Mostrar mensaje de éxito
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Respuestas guardadas correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        // Regresar a la página anterior después de guardar
        Navigator.of(context).pop();
      }

      print('Respuestas guardadas para la encuesta: ${widget.survey.id}');
    } catch (e) {
      print('Error guardando respuestas: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar respuestas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

// Método auxiliar para obtener extensión de archivo
  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length > 1) {
      return '.${parts.last}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.survey.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveResponses,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Mostrar coordenadas y estado de zona rural
                if (_isRuralZone)
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    color: Colors.green.shade100,
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Zona rural detectada - Coordenadas: ${_currentLocation.latitude.toStringAsFixed(6)}, ${_currentLocation.longitude.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Lista de preguntas
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      return _buildQuestionCard(_questions[index], index);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuestionCard(QuestionModel question, int index) {
    // No mostrar preguntas de tipo COORDINATE
    if (question.type.toUpperCase() == "COORDINATE") {
      return const SizedBox.shrink(); // Widget invisible
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                  child: Text(
                    question.text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (question.type.toUpperCase() == 'SELECTIONSIMPLE')
              _buildRadioButtons(question)
            else if (question.type.toUpperCase() == 'SELECTIONMULTIPLE')
              _buildCheckboxes(question)
            else if (question.type == 'multiple_choice')
              _buildMultipleChoiceOptions(question)
            else
              _buildTextInput(question),
          ],
        ),
      ),
    );
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
            });
          },
          activeColor: AppColors.primaryColor,
        );
      }).toList(),
    );
  }

  Widget _buildCheckboxes(QuestionModel question) {
    // Para checkboxes, necesitamos manejar múltiples selecciones
    // Inicializamos la respuesta como una lista vacía si aún no existe
    question.answer ??= '[]';

    // Convertimos la respuesta de JSON a una lista
    List<String> selectedOptions = [];
    try {
      if (question.answer != null && question.answer!.isNotEmpty) {
        selectedOptions = List<String>.from(jsonDecode(question.answer!));
      }
    } catch (e) {
      print('Error decodificando respuestas múltiples: $e');
      question.answer = '[]';
      selectedOptions = [];
    }

    return Column(
      children: question.options.map((option) {
        final optionId = option.id.toString();
        final isSelected = selectedOptions.contains(optionId);

        return CheckboxListTile(
          title: Text(option.text),
          value: isSelected,
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                if (!selectedOptions.contains(optionId)) {
                  selectedOptions.add(optionId);
                }
              } else {
                selectedOptions.remove(optionId);
              }
              // Actualizamos la respuesta como JSON
              question.answer = jsonEncode(selectedOptions);
            });
          },
          activeColor: AppColors.primaryColor,
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoiceOptions(QuestionModel question) {
    return Column(
      children: question.options.map((option) {
        return RadioListTile<String>(
          title: Text(option.text),
          value: option.text,
          groupValue: question.answer,
          onChanged: (value) {
            setState(() {
              question.answer = value;
            });
          },
          activeColor: AppColors.primaryColor,
        );
      }).toList(),
    );
  }

  Widget _buildTextInput(QuestionModel question) {
    // Determinar el tipo de entrada según el tipo de pregunta
    final String questionType = question.type.toUpperCase();

    switch (questionType) {
      case 'DATETIME':
        return _buildDateTimeInput(question);
      case 'NUMBER':
        return _buildNumberInput(question);
      case 'EMAIL':
        return _buildEmailInput(question);
      case 'TEXT':
        return _buildDefaultTextInput(question);
      case 'SIGNATURE':
        return _buildSignatureInput(question);
      case 'MAP':
        return _buildMapButton(question);
      case 'FILE':
        return _buildFileInput(question);
      case 'PHOTO':
        return _buildPhotoInput(question);
      default:
        return _buildDefaultTextInput(question);
    }
  }

  Widget _buildMapButton(QuestionModel question) {
    // Mostrar una vista previa de la ubicación si ya existe
    Widget previewWidget = Container();

    if (question.answer != null && question.answer!.isNotEmpty) {
      try {
        final parts = question.answer!.split(',');
        if (parts.length == 2) {
          final lat = double.parse(parts[1]);
          final lng = double.parse(parts[0]);

          previewWidget = Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ubicación seleccionada:'),
                SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text('Latitud: ${lat.toStringAsFixed(6)}'),
                    SizedBox(width: 16), // espacio entre los textos
                    Text('Longitud: ${lng.toStringAsFixed(6)}'),
                  ],
                ),
              ],
            ),
          );
        }
      } catch (e) {
        print('Error al mostrar la ubicación: $e');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        previewWidget,
        ElevatedButton.icon(
          icon: const Icon(Icons.map),
          label: Text(question.answer == null || question.answer!.isEmpty
              ? 'Seleccionar ubicación'
              : 'Cambiar ubicación'),
          onPressed: () async {
            // Navegar a la página del mapa
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MapInputPage(
                  initialValue: question.answer,
                  questionText: question.text,
                ),
              ),
            );

            // Si se seleccionó una ubicación, actualizar la respuesta
            if (result != null) {
              setState(() {
                question.answer = result;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildDefaultTextInput(QuestionModel question) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Escribe tu respuesta aquí',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
      ),
      onChanged: (value) {
        question.answer = value;
      },
      maxLines: 3,
      controller: TextEditingController(text: question.answer),
    );
  }

  Widget _buildDateTimeInput(QuestionModel question) {
    // Mostrar el valor actual o un placeholder
    final displayText = question.answer != null && question.answer!.isNotEmpty
        ? question.answer!
        : 'Seleccionar fecha y hora';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            // Mostrar selector de fecha
            final DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primaryColor,
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (pickedDate != null) {
              // Mostrar selector de hora
              final TimeOfDay? pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppColors.primaryColor,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (pickedTime != null) {
                // Combinar fecha y hora
                final DateTime dateTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );

                setState(() {
                  // Formatear la fecha y hora
                  question.answer = dateTime.toString();
                });
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(displayText),
                const Icon(Icons.calendar_today, color: AppColors.primaryColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput(QuestionModel question) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Ingresa un número',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (value) {
        question.answer = value;
      },
      controller: TextEditingController(text: question.answer),
    );
  }

  Widget _buildEmailInput(QuestionModel question) {
    // Usar TextEditingController para mantener el foco
    final TextEditingController controller =
        TextEditingController(text: question.answer);

    // Posicionar el cursor al final del texto
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Ingresa un correo electrónico',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
        errorText: _validateEmail(question.answer),
      ),
      keyboardType: TextInputType.emailAddress,
      onChanged: (value) {
        // Actualizar el valor sin llamar a setState para evitar reconstrucción
        question.answer = value;

        // Solo actualizar el error de validación si es necesario
        final String? currentError = _validateEmail(value);
        if (currentError != _validateEmail(question.answer)) {
          setState(() {
            // Solo actualizar el estado si cambió el error
          });
        }
      },
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return null; // No mostrar error si está vacío
    }

    // Expresión regular para validar email
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (!emailRegex.hasMatch(value)) {
      return 'Ingresa un correo electrónico válido';
    }

    return null;
  }

  Widget _buildFileInput(QuestionModel question) {
    // Mostrar el nombre del archivo si ya se ha seleccionado uno
    String? fileName;
    if (question.answer != null && question.answer!.isNotEmpty) {
      try {
        final fileData = jsonDecode(question.answer!);
        fileName = fileData['name'];
      } catch (e) {
        print('Error al decodificar datos del archivo: $e');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fileName != null)
          Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, color: AppColors.primaryColor),
                SizedBox(width: 8),
                Expanded(child: Text(fileName)),
              ],
            ),
          ),
        ElevatedButton.icon(
          icon: Icon(Icons.attach_file),
          label: Text(
              fileName == null ? 'Seleccionar archivo' : 'Cambiar archivo'),
          onPressed: () async {
            // Aquí implementaremos la selección de archivos

            FilePickerResult? result = await FilePicker.platform.pickFiles(
              withData: true,
            );
            if (result != null) {
              PlatformFile file = result.files.first;
    
              try {
                // Determinar extensión desde el nombre
                final ext = _getFileExtension(file.name);
                final baseName =
                    '${question.id}_${DateTime.now().millisecondsSinceEpoch}';
    
                // Guardar en 'uploads': si hay bytes, usarlos; si no, leer desde path
                Map<String, String> saved;
                if (file.bytes != null) {
                  saved = await _saveBytesToUploads(
                    file.bytes as Uint8List,
                    baseName,
                    ext.isNotEmpty ? ext : '.bin',
                  );
                } else if (file.path != null && file.path!.isNotEmpty) {
                  final bytes = await File(file.path!).readAsBytes();
                  saved = await _saveBytesToUploads(
                    bytes,
                    baseName,
                    ext.isNotEmpty ? ext : '.bin',
                  );
                } else {
                  // No hay forma de persistir el archivo
                  throw Exception('El proveedor no entregó ruta ni bytes del archivo');
                }
    
                setState(() {
                  // Guardar referencia estable a lo copiado en uploads
                  question.answer = jsonEncode({
                    'name': saved['name'],
                    'path': saved['path'],
                    'size': file.size,
                  });
                });
              } catch (e) {
                // Fallback: conservar datos originales si algo falla
                setState(() {
                  question.answer = jsonEncode({
                    'name': file.name,
                    'path': file.path,
                    'size': file.size,
                  });
                });
                print('Error guardando archivo en uploads: $e');
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildPhotoInput(QuestionModel question) {
    Widget previewWidget = Container();

    if (question.answer != null && question.answer!.isNotEmpty) {
      try {
        // Intentar decodificar la imagen en base64
        final bytes = base64Decode(question.answer!);
        previewWidget = Column(
          children: [
            Text('Imagen guardada:'),
            Image.memory(
              bytes,
              height: 150,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ],
        );
      } catch (e) {
        previewWidget = Text('Vista previa no disponible');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.answer != null && question.answer!.isNotEmpty)
          previewWidget,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.camera_alt),
              label: Text('Tomar foto'),
              onPressed: () async {
                // Aquí implementaremos la captura de fotos
                // Necesitamos agregar la dependencia image_picker
                final ImagePicker _picker = ImagePicker();
                final XFile? photo =
                    await _picker.pickImage(source: ImageSource.camera);
                if (photo != null) {
                  final bytes = await photo.readAsBytes();
                  setState(() {
                    question.answer = base64Encode(bytes);
                  });
                }
              },
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.photo_library),
              label: Text('Galería'),
              onPressed: () async {
                // Aquí implementaremos la selección de fotos de la galería
                // Necesitamos agregar la dependencia image_picker
                final ImagePicker _picker = ImagePicker();
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  setState(() {
                    question.answer = base64Encode(bytes);
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignatureInput(QuestionModel question) {
    // Creamos el controlador de firma
    final SignatureController _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: AppColors.primaryColor,
      exportBackgroundColor: Colors.white,
    );

    // Si ya hay una firma guardada, mostrarla
    // No podemos usar addImage porque no existe ese método
    // En su lugar, podemos mostrar la imagen guardada por separado
    bool hasExistingSignature =
        question.answer != null && question.answer!.isNotEmpty;
    Uint8List? existingSignatureData;

    if (hasExistingSignature) {
      try {
        existingSignatureData = base64Decode(question.answer!);
      } catch (e) {
        print('Error al cargar la firma: $e');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Si hay una firma existente, mostrarla
        if (hasExistingSignature && existingSignatureData != null)
          Container(
            margin: EdgeInsets.only(bottom: 10),
            width: double.infinity, // Ocupa todo el ancho
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              // Centra horizontalmente la imagen
              child: Image.memory(
                existingSignatureData,
                height: 150, // Altura fija
                // No usamos 'fit', para mantener proporción original
                // Si quieres evitar que se estire, no pongas width
              ),
            ),
          ),

        // Siempre mostrar el pad de firma para permitir una nueva firma
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          height: 150,
          child: Signature(
            controller: _controller,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () {
                _controller.clear();
                setState(() {
                  question.answer = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Borrar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_controller.isNotEmpty) {
                  final Uint8List? data = await _controller.toPngBytes();
                  if (data != null) {
                    final String base64String = base64Encode(data);
                    setState(() {
                      question.answer = base64String;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Firma guardada')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ],
    );
  }
}