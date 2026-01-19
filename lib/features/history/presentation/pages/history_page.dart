import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/history/data/models/history_model.dart';
import 'package:surveygo/features/history/presentation/widgets/history_item.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _isLoading = false;
  List<HistoryModel> _historyItems = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('Iniciando carga del historial...');

      // Obtener encuestas de la base de datos local
      final surveys = await _dbHelper.getSurveys();
      print('Encuestas encontradas: ${surveys.length}');

      final historyItems = <HistoryModel>[];

      for (var survey in surveys) {
        print('Procesando encuesta: ${survey.id} - ${survey.cNombreEncuesta}');

        // Obtener todas las respuestas para esta encuesta
        final allResponses =
            await _dbHelper.getResponsesBySurvey(survey.id.toString());

        print(
            'Respuestas encontradas para encuesta ${survey.id}: ${allResponses.length}');

        if (allResponses.isEmpty) continue;

        // Obtener las preguntas de esta encuesta
        final questions = await _dbHelper.getQuestions(survey.id);
        print(
            'Preguntas encontradas para encuesta ${survey.id}: ${questions.length}');

        final Map<int, String> questionTexts = {};
        for (var question in questions) {
          questionTexts[question.id] = question.cPregunta;
        }

        // Agrupar respuestas por response_set_id
        final Map<String, List<Map<String, dynamic>>> responseGroups = {};

        for (var response in allResponses) {
          final responseSetId = response['response_set_id'] ?? 'default';
          if (!responseGroups.containsKey(responseSetId)) {
            responseGroups[responseSetId] = [];
          }

          // Crear una copia mutable de la respuesta
          final mutableResponse = Map<String, dynamic>.from(response);

          // Añadir el texto de la pregunta a la respuesta
          final questionId =
              int.tryParse(mutableResponse['id_pregunta'].toString()) ?? 0;
          mutableResponse['question_text'] =
              questionTexts[questionId] ?? 'Pregunta no encontrada';

          responseGroups[responseSetId]!.add(mutableResponse);
        }

        print(
            'Grupos de respuestas para encuesta ${survey.id}: ${responseGroups.length}');

        // Crear un elemento de historial para cada conjunto de respuestas
        responseGroups.forEach((responseSetId, responses) {
          // Ordenar respuestas por fecha de creación (más reciente primero)
          responses.sort((a, b) {
            final dateA = a['fecha_creacion'] ?? '';
            final dateB = b['fecha_creacion'] ?? '';
            return dateB.compareTo(dateA);
          });

          final completedDate = DateTime.parse(
              responses.first['fecha_creacion'] ??
                  DateTime.now().toIso8601String());

          print('Creando HistoryModel para responseSetId: $responseSetId');

          historyItems.add(
            HistoryModel(
              id: survey.id,
              survey: SurveyModel(
                id: survey.id,
                title: survey.cNombreEncuesta,
                description: survey.cTipo,
                questions: [],
                isCompleted: true,
              ),
              completedDate: completedDate,
              status: 'completed',
              responses: responses,
              responseSetId: responseSetId,
            ),
          );
        });
      }

      // Ordenar por fecha de completado (más reciente primero)
      historyItems.sort((a, b) => b.completedDate.compareTo(a.completedDate));

      print('Total de elementos de historial creados: ${historyItems.length}');

      setState(() {
        _historyItems = historyItems;
      });
    } catch (e) {
      print('Error loading history: $e');
      print('Stack trace: ${StackTrace.current}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor))
          : _historyItems.isEmpty
              ? const Center(child: Text('No hay encuestas completadas'))
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  color: AppColors.primaryColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      final formattedDate = DateFormat('dd/MM/yyyy HH:mm')
                          .format(item.completedDate);

                      return HistoryItem(
                        historyItem: item,
                        subtitle: 'Completada: $formattedDate',
                        onTap: () {
                          _showResponseDetails(item);
                        },
                      );
                    },
                  ),
                ),
    );
  }

  void _showResponseDetails(HistoryModel historyItem) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    historyItem.survey.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fecha: ${historyItem.completedDate.toLocal().toString().split('.')[0]}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  if (historyItem.responseSetId != 'default') ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID de respuesta: ${historyItem.responseSetId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Respuestas (${historyItem.responses.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: historyItem.responses.length,
                      itemBuilder: (context, index) {
                        final response = historyItem.responses[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  response['question_text'] ??
                                      'Pregunta no encontrada',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text('Tipo: ${response['c_tipo_pregunta']}'),
                                const SizedBox(height: 4),

                                // Mostrar respuesta según el tipo
                                _buildResponseWidget(response),

                                if (response['glgis'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Coordenadas: ${response['glgis']}'),
                                ],
                              ],
                            ),
                          ),
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

  Widget _buildResponseWidget(Map<String, dynamic> response) {
    final tipoRespuesta =
        response['c_tipo_pregunta']?.toString().toLowerCase() ?? '';
    final raw = response['c_respuesta'];
    final respuestaStr = raw?.toString() ?? '';

    // Mostrar imágenes (foto/firma)
    if (tipoRespuesta.contains('photo') ||
        tipoRespuesta.contains('image') ||
        tipoRespuesta.contains('firma') ||
        tipoRespuesta.contains('signature')) {
      if (respuestaStr.isNotEmpty) {
        try {
          // Primero: si c_respuesta es una ruta de archivo, mostrar desde disco
          final file = File(respuestaStr);
          if (file.existsSync()) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Respuesta:'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 100,
                        color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const Text('Error al cargar la imagen'),
                      );
                    },
                  ),
                ),
                if (response['c_nombre_file'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      'Archivo: ${response['c_nombre_file']}${response['c_extension'] ?? ''}'),
                ],
              ],
            );
          }

          // Si no existe como archivo, intentar decodificar como Base64
          final bytes = base64Decode(respuestaStr);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Respuesta:'),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: 100,
                      color: Colors.grey[300],
                      alignment: Alignment.center,
                      child: const Text('Error al cargar la imagen'),
                    );
                  },
                ),
              ),
              if (response['c_nombre_file'] != null) ...[
                const SizedBox(height: 4),
                Text(
                    'Archivo: ${response['c_nombre_file']}${response['c_extension'] ?? ''}'),
              ],
            ],
          );
        } catch (e) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Respuesta:'),
              const SizedBox(height: 8),
              Text('No se pudo cargar la imagen. $e'),
              Text(
                'Valor recibido: $respuestaStr',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          );
        }
      }
      return const Text('Respuesta: Sin imagen');
    } else if (tipoRespuesta.contains('file')) {
      // Visualización mejorada para archivos
      final nombreFile = response['c_nombre_file']?.toString() ?? '';
      final extension =
          (response['c_extension']?.toString() ?? '').toLowerCase();
      final file = File(respuestaStr);
      final exists = respuestaStr.isNotEmpty && file.existsSync();

      // Detectar si es imagen por extensión
      final isImage = extension.endsWith('.png') ||
          extension.endsWith('.jpg') ||
          extension.endsWith('.jpeg') ||
          extension.endsWith('.gif') ||
          extension.endsWith('.bmp') ||
          extension.endsWith('.webp');

      // Si es imagen y existe el archivo, mostrar vista previa
      if (exists && isImage) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Respuesta:'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 200,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    height: 100,
                    color: Colors.grey[300],
                    alignment: Alignment.center,
                    child: const Text('Error al cargar la imagen'),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.insert_photo, color: AppColors.primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nombreFile.isNotEmpty
                        ? nombreFile
                        : file.uri.pathSegments.last,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        );
      }

      // Para PDF u otros tipos: card con icono, nombre y tamaño
      final fileSizeText = exists
          ? '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB'
          : 'Tamaño no disponible';

      IconData icon;
      Color iconColor;
      if (extension.endsWith('.pdf')) {
        icon = Icons.picture_as_pdf;
        iconColor = Colors.red;
      } else if (extension.endsWith('.doc') || extension.endsWith('.docx')) {
        icon = Icons.description;
        iconColor = AppColors.primaryColor;
      } else if (extension.endsWith('.xls') || extension.endsWith('.xlsx')) {
        icon = Icons.table_chart;
        iconColor = Colors.green;
      } else {
        icon = Icons.insert_drive_file;
        iconColor = AppColors.primaryColor;
      }

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Archivo adjunto'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombreFile.isNotEmpty
                            ? nombreFile
                            : (exists ? file.uri.pathSegments.last : 'Archivo'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exists ? fileSizeText : 'Archivo no disponible',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Mostrar ruta solo si no existe o para depurar
            if (!exists)
              Text('Ruta: $respuestaStr',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
    } else if (tipoRespuesta.contains('map') ||
        tipoRespuesta.contains('coordinate')) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Respuesta: Coordenadas registradas'),
        ],
      );
    }

    // Para otros tipos de respuestas
    return Text(
        'Respuesta: ${respuestaStr.isNotEmpty ? respuestaStr : 'No disponible'}');
  }
}
