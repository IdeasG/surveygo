import 'package:flutter/material.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';
import 'package:surveygo/features/surveys/presentation/pages/survey_detail_page.dart';
import 'package:surveygo/features/surveys/presentation/pages/survey_map_page.dart';
import 'package:surveygo/features/surveys/presentation/widgets/survey_card.dart';
import 'package:surveygo/services/survey_sync_service.dart';

class SurveysPage extends StatefulWidget {
  const SurveysPage({Key? key}) : super(key: key);

  @override
  State<SurveysPage> createState() => _SurveysPageState();
}

class _SurveysPageState extends State<SurveysPage> {
  bool _isLoading = false;
  List<SurveyModel> _surveys = [];
  final SurveySyncService _syncService = SurveySyncService();

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  Future<void> _loadSurveys() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Cargar encuestas desde SQLite con sus preguntas
      final localSurveys = await _syncService.getLocalSurveysWithQuestions();

      // Convertir SurveyRolModel a SurveyModel
      final convertedSurveys = localSurveys
          .map((rolSurvey) => _convertToSurveyModel(rolSurvey))
          .toList();

      setState(() {
        _surveys = convertedSurveys;
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando encuestas: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar encuestas')),
        );
      }
    }
  }

  // Método para convertir SurveyRolModel a SurveyModel
  SurveyModel _convertToSurveyModel(SurveyRolModel rolSurvey) {
    return SurveyModel(
      id: rolSurvey.id,
      title: rolSurvey.cNombreEncuesta,
      description: 'Tipo: ${rolSurvey.cTipo}',
      type: rolSurvey.cTipo,
      workspace: rolSurvey.fuenteDatos?.cWorkspace ?? '',
      layer: rolSurvey.fuenteDatos?.cCapa ?? '',
      questions: rolSurvey.preguntas
          .map((pregunta) => _convertToQuestionModel(pregunta))
          .toList(),
      isCompleted: false,
    );
  }

  // Método para convertir SurveyQuestionModel a QuestionModel
  QuestionModel _convertToQuestionModel(SurveyQuestionModel pregunta) {
    List<OptionModel> options = [];

    // Si hay opciones en j_opciones, convertirlas a OptionModel
    if (pregunta.jOpciones != null &&
        pregunta.jOpciones!.containsKey('opciones') &&
        pregunta.jOpciones!['opciones'] is List) {
      final List<dynamic> opcionesList = pregunta.jOpciones!['opciones'];
      options = opcionesList.asMap().entries.map((entry) {
        return OptionModel(
          id: entry.key,
          text: entry.value.toString(),
        );
      }).toList();
    }

    return QuestionModel(
      id: pregunta.id,
      text: pregunta.cPregunta,
      type: pregunta.cTipo.toLowerCase(),
      options: options,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encuestas'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor))
          : _surveys.isEmpty
              ? const Center(child: Text('No hay encuestas disponibles'))
              : RefreshIndicator(
                  onRefresh: _loadSurveys,
                  color: AppColors.primaryColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _surveys.length,
                    itemBuilder: (context, index) {
                      return SurveyCard(
                        survey: _surveys[index],
                        onTap: () {
                          final survey = _surveys[index];
                          if ((survey.type).toUpperCase() == 'BASADO') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SurveyMapPage(
                                  survey: survey,
                                ),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SurveyDetailPage(
                                  survey: survey,
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
