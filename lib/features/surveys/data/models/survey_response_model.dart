import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';

class SurveyResponseModel {
  final String status;
  final String message;
  final List<SurveyRolModel> data;

  SurveyResponseModel({
    required this.status,
    required this.message,
    required this.data,
  });

  factory SurveyResponseModel.fromJson(Map<String, dynamic> json) {
    return SurveyResponseModel(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      data: (json['data'] as List? ?? [])
          .map((item) => SurveyRolModel.fromJson(item))
          .toList(),
    );
  }
}

class SurveyRolModel {
  final int id;
  final String cNombreEncuesta;
  final String cTipo;
  final DateTime dFechaCreacion;
  final int idRol;
  final int idFuente;
  final FuenteDatos? fuenteDatos;
  final List<SurveyQuestionModel> preguntas;

  SurveyRolModel({
    required this.id,
    required this.cNombreEncuesta,
    required this.cTipo,
    required this.dFechaCreacion,
    required this.idRol,
    required this.idFuente,
    this.fuenteDatos,
    this.preguntas = const [],
  });

  factory SurveyRolModel.fromJson(Map<String, dynamic> json) {
    return SurveyRolModel(
      id: json['id'] ?? 0,
      cNombreEncuesta: json['c_nombre_encuesta'] ?? '',
      cTipo: json['c_tipo'] ?? '',
      dFechaCreacion: json['d_fecha_creacion'] != null
          ? DateTime.parse(json['d_fecha_creacion'])
          : DateTime.now(),
      idRol: json['id_rol'] ?? 0,
      idFuente: json['id_fuente'] ?? 0,
      fuenteDatos: json['fuenteDatos'] != null
          ? FuenteDatos.fromJson(json['fuenteDatos'])
          : null,
      preguntas: json['preguntas'] != null
          ? (json['preguntas'] as List)
              .map((item) => SurveyQuestionModel.fromJson(item))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'c_nombre_encuesta': cNombreEncuesta,
      'c_tipo': cTipo,
      'd_fecha_creacion': dFechaCreacion.toIso8601String(),
      'id_rol': idRol,
      'id_fuente': idFuente,
      'fuenteDatos': fuenteDatos?.toJson(),
      'preguntas': preguntas.map((pregunta) => pregunta.toJson()).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre_encuesta': cNombreEncuesta,
      'tipo': cTipo,
      'fecha_creacion': dFechaCreacion.toIso8601String(),
      'id_rol': idRol,
      'id_fuente': idFuente,
    };
  }
}

class FuenteDatos {
  final int id;
  final String cEsquema;
  final String cTabla;
  final String cWorkspace;
  final String cCapa;

  FuenteDatos({
    required this.id,
    required this.cEsquema,
    required this.cTabla,
    required this.cWorkspace,
    required this.cCapa,
  });

  factory FuenteDatos.fromJson(Map<String, dynamic> json) {
    return FuenteDatos(
      id: json['id'] ?? 0,
      cEsquema: json['c_esquema'] ?? '',
      cTabla: json['c_tabla'] ?? '',
      cWorkspace: json['c_workspace'] ?? '',
      cCapa: json['c_capa'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'c_esquema': cEsquema,
      'c_tabla': cTabla,
      'c_workspace': cWorkspace,
      'c_capa': cCapa,
    };
  }
}
