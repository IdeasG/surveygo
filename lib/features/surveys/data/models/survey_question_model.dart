import 'dart:convert';

class SurveyQuestionModel {
  final int id;
  final int idEncuesta;
  final String cCampo;
  final String cPregunta;
  final String cTipo;
  final Map<String, dynamic>? jOpciones;

  SurveyQuestionModel({
    required this.id,
    required this.idEncuesta,
    required this.cCampo,
    required this.cPregunta,
    required this.cTipo,
    this.jOpciones,
  });

  factory SurveyQuestionModel.fromJson(Map<String, dynamic> json) {
    return SurveyQuestionModel(
      id: json['id'] ?? 0,
      idEncuesta: json['id_encuesta'] ?? 0,
      cCampo: json['c_campo'] ?? '',
      cPregunta: json['c_pregunta'] ?? '',
      cTipo: json['c_tipo'] ?? '',
      jOpciones: json['j_opciones'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_encuesta': idEncuesta,
      'c_campo': cCampo,
      'c_pregunta': cPregunta,
      'c_tipo': cTipo,
      'j_opciones': jOpciones,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'id_encuesta': idEncuesta,
      'c_campo': cCampo,
      'c_pregunta': cPregunta,
      'c_tipo': cTipo,
      'j_opciones': jOpciones != null ? jsonEncode(jOpciones) : null,
    };
  }

  static SurveyQuestionModel fromMap(Map<String, dynamic> map) {
    return SurveyQuestionModel(
      id: map['id'],
      idEncuesta: map['id_encuesta'],
      cCampo: map['c_campo'],
      cPregunta: map['c_pregunta'],
      cTipo: map['c_tipo'],
      jOpciones: map['j_opciones'] != null ? jsonDecode(map['j_opciones']) : null,
    );
  }
}