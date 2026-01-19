import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/http_provider.dart';

class SurveySyncService {
  final HttpProvider _httpProvider = HttpProvider();
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<bool> syncSurveys() async {
    try {
      // Obtener encuestas del servidor
      final response = await _httpProvider.get('/encuestas/encuesta/porRol');

      // Convertir la respuesta a nuestro modelo
      final surveyResponse = SurveyResponseModel.fromJson(response);

      if (surveyResponse.status == 'success') {
        // Eliminar encuestas y preguntas existentes
        await _databaseHelper.deleteAllQuestions();
        await _databaseHelper.deleteAllSurveys();

        // Guardar nuevas encuestas
        await _databaseHelper.insertSurveys(surveyResponse.data);

        // Guardar preguntas de cada encuesta
        for (var survey in surveyResponse.data) {
          if (survey.preguntas.isNotEmpty) {
            await _databaseHelper.insertQuestions(survey.preguntas);
          }
        }

        return true;
      }

      return false;
    } catch (e) {
      print('Error sincronizando encuestas: $e');
      return false;
    }
  }

  Future<List<SurveyRolModel>> getLocalSurveys() async {
    return await _databaseHelper.getSurveys();
  }

  // Método para obtener encuestas locales con sus preguntas
  Future<List<SurveyRolModel>> getLocalSurveysWithQuestions() async {
    List<SurveyRolModel> surveys = await _databaseHelper.getSurveys();

    // Para cada encuesta, obtener sus preguntas
    for (int i = 0; i < surveys.length; i++) {
      List<SurveyQuestionModel> questions =
          await _databaseHelper.getQuestions(surveys[i].id);
      surveys[i] = SurveyRolModel(
        id: surveys[i].id,
        cNombreEncuesta: surveys[i].cNombreEncuesta,
        cTipo: surveys[i].cTipo,
        dFechaCreacion: surveys[i].dFechaCreacion,
        idRol: surveys[i].idRol,
        idFuente: surveys[i].idFuente,
        preguntas: questions,
      );
    }

    return surveys;
  }
}
