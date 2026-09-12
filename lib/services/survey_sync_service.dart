import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';
import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/http_provider.dart';

class SurveySyncService {
  final HttpProvider _httpProvider = HttpProvider();
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<bool> syncSurveys() async {
    try {
      final response = await _httpProvider.get('/encuestas/encuesta/porRol');
      final surveyResponse = SurveyResponseModel.fromJson(response);

      if (surveyResponse.status == 'success' && surveyResponse.data.isNotEmpty) {
        await _databaseHelper.deleteAllQuestions();
        await _databaseHelper.deleteAllSurveys();
        await _databaseHelper.insertSurveys(surveyResponse.data);

        for (var survey in surveyResponse.data) {
          if (survey.preguntas.isNotEmpty) {
            await _databaseHelper.insertQuestions(survey.preguntas);
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error sincronizando encuestas con el servidor: $e');
      return false;
    }
  }

  Future<List<SurveyRolModel>> getLocalSurveys() async {
    return await _databaseHelper.getSurveys();
  }

  Future<void> seedDemoSurveysIfEmpty() async {
    final existing = await _databaseHelper.getSurveys();
    if (existing.isNotEmpty) return;

    // 1. Censo Urbano & Catastro Predial (Polígonos)
    final survey1 = SurveyRolModel(
      id: 101,
      cNombreEncuesta: 'Censo Urbano & Catastro Predial',
      cTipo: 'POLYGON',
      dFechaCreacion: DateTime.now(),
      idRol: 1,
      idFuente: 1,
      preguntas: [
        SurveyQuestionModel(
          id: 1001,
          idEncuesta: 101,
          cCampo: 'titular',
          cPregunta: 'Nombre Completo del Titular o Conductor',
          cTipo: 'TEXT',
          isRequired: true,
          hint: 'Ej: Juan Pérez Gómez',
        ),
        SurveyQuestionModel(
          id: 1002,
          idEncuesta: 101,
          cCampo: 'uso_suelo',
          cPregunta: 'Uso Predominante del Predio',
          cTipo: 'SELECTIONSIMPLE',
          isRequired: true,
          jOpciones: {
            'opciones': ['Vivienda / Residencial', 'Comercial', 'Industrial / Taller', 'Educación / Salud', 'Terreno Vacante']
          },
        ),
        SurveyQuestionModel(
          id: 1003,
          idEncuesta: 101,
          cCampo: 'poligono_predio',
          cPregunta: 'Delimitación y Área del Predio (Polígono)',
          cTipo: 'POLYGON',
          isRequired: true,
          geometryType: 'POLYGON',
          hint: 'Dibuje el perímetro en el mapa o marque los vértices con GPS',
        ),
        SurveyQuestionModel(
          id: 1004,
          idEncuesta: 101,
          cCampo: 'servicios',
          cPregunta: 'Servicios Básicos Instalados',
          cTipo: 'SELECTIONMULTIPLE',
          jOpciones: {
            'opciones': ['Agua Potable', 'Alcantarillado', 'Energía Eléctrica', 'Gas Natural / Red', 'Internet Fibra']
          },
        ),
        SurveyQuestionModel(
          id: 1005,
          idEncuesta: 101,
          cCampo: 'foto_fachada',
          cPregunta: 'Fotografía de la Fachada Principal',
          cTipo: 'PHOTO',
          isRequired: true,
        ),
        SurveyQuestionModel(
          id: 1006,
          idEncuesta: 101,
          cCampo: 'firma_inspector',
          cPregunta: 'Firma de Conformidad del Inspector',
          cTipo: 'SIGNATURE',
          isRequired: true,
        ),
      ],
    );

    // 2. Inspección Vial y Mantenimiento de Redes (Líneas / Rutas)
    final survey2 = SurveyRolModel(
      id: 102,
      cNombreEncuesta: 'Inspección Vial y Redes de Transporte',
      cTipo: 'LINE',
      dFechaCreacion: DateTime.now(),
      idRol: 1,
      idFuente: 1,
      preguntas: [
        SurveyQuestionModel(
          id: 2001,
          idEncuesta: 102,
          cCampo: 'nombre_via',
          cPregunta: 'Nombre de la Vía / Avenida / Jirón',
          cTipo: 'TEXT',
          isRequired: true,
          hint: 'Ej: Av. Los Libertadores Tramo 2',
        ),
        SurveyQuestionModel(
          id: 2002,
          idEncuesta: 102,
          cCampo: 'trazo_ruta',
          cPregunta: 'Trazado y Longitud del Tramo (Ruta)',
          cTipo: 'LINE',
          isRequired: true,
          geometryType: 'LINESTRING',
          hint: 'Trace la línea continua de la vía para calcular la distancia',
        ),
        SurveyQuestionModel(
          id: 2003,
          idEncuesta: 102,
          cCampo: 'tipo_pavimento',
          cPregunta: 'Tipo de Superficie de Rodadura',
          cTipo: 'SELECTIONSIMPLE',
          isRequired: true,
          jOpciones: {
            'opciones': ['Asfalto en Caliente', 'Concreto Hidráulico', 'Adoquinado', 'Afirmado / Trocha']
          },
        ),
        SurveyQuestionModel(
          id: 2004,
          idEncuesta: 102,
          cCampo: 'estado_conservacion',
          cPregunta: 'Estado de Conservación de la Vía',
          cTipo: 'SELECTIONSIMPLE',
          isRequired: true,
          jOpciones: {
            'opciones': ['Excelente / Nuevo', 'Bueno (Baches menores)', 'Regular (Desgaste superficial)', 'Crítico (Requiere recapeo total)']
          },
        ),
        SurveyQuestionModel(
          id: 2005,
          idEncuesta: 102,
          cCampo: 'foto_evidencia',
          cPregunta: 'Foto del Estado de la Vía',
          cTipo: 'PHOTO',
        ),
      ],
    );

    // 3. Inventario de Equipamiento Urbano (Puntos GPS)
    final survey3 = SurveyRolModel(
      id: 103,
      cNombreEncuesta: 'Inventario Rápido de Mobiliario y Equipamiento',
      cTipo: 'POINT',
      dFechaCreacion: DateTime.now(),
      idRol: 1,
      idFuente: 1,
      preguntas: [
        SurveyQuestionModel(
          id: 3001,
          idEncuesta: 103,
          cCampo: 'tipo_elemento',
          cPregunta: 'Tipo de Equipamiento / Mobiliario',
          cTipo: 'SELECTIONSIMPLE',
          isRequired: true,
          jOpciones: {
            'opciones': ['Poste de Alumbrado LED', 'Hidrante contra Incendios', 'Semáforo Vehicular', 'Cámara de Seguridad Urbana', 'Contenedor de Residuos']
          },
        ),
        SurveyQuestionModel(
          id: 3002,
          idEncuesta: 103,
          cCampo: 'ubicacion_gps',
          cPregunta: 'Posición GPS del Elemento',
          cTipo: 'MAP',
          isRequired: true,
          geometryType: 'POINT',
          allowGpsOnly: true,
          hint: 'Presione "Mi GPS" frente al elemento para georreferenciarlo',
        ),
        SurveyQuestionModel(
          id: 3003,
          idEncuesta: 103,
          cCampo: 'estado_operativo',
          cPregunta: 'Estado de Funcionamiento',
          cTipo: 'SELECTIONSIMPLE',
          isRequired: true,
          jOpciones: {
            'opciones': ['Operativo al 100%', 'Mantenimiento Preventivo Requerido', 'Inoperativo / Averiado']
          },
        ),
        SurveyQuestionModel(
          id: 3004,
          idEncuesta: 103,
          cCampo: 'foto_elemento',
          cPregunta: 'Fotografía del Elemento',
          cTipo: 'PHOTO',
        ),
        SurveyQuestionModel(
          id: 3005,
          idEncuesta: 103,
          cCampo: 'observaciones',
          cPregunta: 'Observaciones Técnicas Adicionales',
          cTipo: 'TEXT',
          hint: 'Indique daños, rotulación, etc.',
        ),
      ],
    );

    await _databaseHelper.insertSurveys([survey1, survey2, survey3]);
    await _databaseHelper.insertQuestions(survey1.preguntas);
    await _databaseHelper.insertQuestions(survey2.preguntas);
    await _databaseHelper.insertQuestions(survey3.preguntas);
  }

  Future<List<SurveyRolModel>> getLocalSurveysWithQuestions() async {
    await seedDemoSurveysIfEmpty();
    List<SurveyRolModel> surveys = await _databaseHelper.getSurveys();

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

  dynamic parseCoordinates(dynamic coordinates) {
    if (coordinates == null) return null;
    if (coordinates is Map) return coordinates;
    final str = coordinates.toString().trim();
    if (str.isEmpty) return null;

    if (str.startsWith('{') && str.endsWith('}')) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is Map && decoded.containsKey('type') && decoded.containsKey('coordinates')) {
          return decoded;
        }
      } catch (_) {}
    }

    try {
      final parsed = GisCalculator.fromGeoJsonOrString(str);
      if (parsed != null) {
        return GisCalculator.toGeoJson(parsed.type, parsed.points);
      }
    } catch (e) {
      debugPrint('Error parseando geometría en sincronización: $e');
    }
    return null;
  }

  Future<bool> sendSingleResponseSet(String responseSetId) async {
    try {
      final db = await _databaseHelper.database;
      final responses = await db.query(
        'survey_responses',
        where: 'response_set_id = ?',
        whereArgs: [responseSetId],
      );

      if (responses.isEmpty) return false;

      final surveyId = responses.first['id_encuesta'].toString();
      List<Map<String, dynamic>> formattedResponses = [];

      for (var response in responses) {
        String? respuesta = response['c_respuesta']?.toString();
        final tipo = response['c_tipo_pregunta']?.toString().toUpperCase();
        final nombreFile = response['c_nombre_file']?.toString();
        final extension = response['c_extension']?.toString();

        if ((tipo == 'PHOTO' || tipo == 'FILE' || tipo == 'SIGNATURE') &&
            respuesta != null &&
            respuesta.isNotEmpty) {
          try {
            final file = File(respuesta);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              respuesta = base64Encode(bytes);
            }
          } catch (e) {
            debugPrint('No se pudo leer archivo para respuesta: $e');
          }
        }

        formattedResponses.add({
          'id_pregunta': int.tryParse(response['id_pregunta'].toString()) ?? 0,
          'c_tipo_pregunta': response['c_tipo_pregunta'],
          'c_respuesta': respuesta,
          'c_nombre_file': nombreFile,
          'c_extension': extension,
          'glgis': response['glgis'] != null ? parseCoordinates(response['glgis']) : null,
        });
      }

      final requestBody = {
        'respuesta': {
          'id_encuesta': int.tryParse(surveyId) ?? 0,
          'id_campo_geometria': null,
          'response_set_id': responseSetId,
        },
        'respuestasPregunta': formattedResponses,
      };

      final result = await _httpProvider.post(
        '/encuestas/respuesta/insertarConPreguntas',
        body: requestBody,
      );

      final success = result != null &&
          (result['status'] == 'success' || result['status'] == 'ok');

      if (success) {
        await _databaseHelper.updateResponseSetStatus(responseSetId, 'SYNCED');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error enviando response_set $responseSetId: $e');
      return false;
    }
  }

  Future<({int successCount, int errorCount, String message})> sendAllCompletedResponses() async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> allResponses = await db.query(
        'survey_responses',
        where: "COALESCE(status, 'COMPLETED') = 'COMPLETED'",
      );

      if (allResponses.isEmpty) {
        return (successCount: 0, errorCount: 0, message: 'No hay encuestas pendientes de sincronizar.');
      }

      final Set<String> responseSetIds = {};
      for (var r in allResponses) {
        final setId = r['response_set_id']?.toString();
        if (setId != null && setId.isNotEmpty) {
          responseSetIds.add(setId);
        }
      }

      int successCount = 0;
      int errorCount = 0;

      for (var setId in responseSetIds) {
        final ok = await sendSingleResponseSet(setId);
        if (ok) {
          successCount++;
        } else {
          errorCount++;
        }
      }

      return (
        successCount: successCount,
        errorCount: errorCount,
        message: errorCount == 0
            ? '¡$successCount encuesta(s) sincronizada(s) con éxito!'
            : 'Sincronizadas: $successCount, Errores: $errorCount',
      );
    } catch (e) {
      debugPrint('Error en sendAllCompletedResponses: $e');
      return (successCount: 0, errorCount: 1, message: 'Error al enviar: $e');
    }
  }
}
