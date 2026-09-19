import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';

class SurveyModel {
  final int id;
  final String title;
  final String description;
  final String type;
  final String workspace;
  final String layer;
  final List<QuestionModel> questions;
  final bool isCompleted;

  SurveyModel({
    required this.id,
    required this.title,
    required this.description,
    this.type = '',
    this.workspace = '',
    this.layer = '',
    required this.questions,
    this.isCompleted = false,
  });

  factory SurveyModel.fromJson(Map<String, dynamic> json) {
    return SurveyModel(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '',
      workspace: json['workspace'] ?? '',
      layer: json['layer'] ?? '',
      questions: (json['questions'] as List? ?? [])
          .map((q) => QuestionModel.fromJson(q))
          .toList(),
      isCompleted: json['is_completed'] ?? false,
    );
  }
}

class QuestionModel {
  final int id;
  final String field;
  final String text;
  final String type; // 'SELECTIONSIMPLE', 'TEXT', 'MAP', 'POLYGON', etc.
  final List<OptionModel> options;
  String? answer;

  // Propiedades avanzadas
  final bool isRequired;
  final String? dependsOnField;
  final dynamic dependsOnValue;
  final String? section;
  final String? hint;
  final String? geometryType;
  final bool allowGpsOnly;
  final double? minValue;
  final double? maxValue;
  final String? regexPattern;
  final bool isPersistent;
  final String? conditionOperator;

  QuestionModel({
    required this.id,
    this.field = '',
    required this.text,
    required this.type,
    required this.options,
    this.answer,
    this.isRequired = false,
    this.dependsOnField,
    this.dependsOnValue,
    this.section,
    this.hint,
    this.geometryType,
    this.allowGpsOnly = false,
    this.minValue,
    this.maxValue,
    this.regexPattern,
    this.isPersistent = false,
    this.conditionOperator = '=',
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] ?? 0,
      field: json['field'] ?? json['c_campo'] ?? '',
      text: json['text'] ?? json['c_pregunta'] ?? '',
      type: json['type'] ?? json['c_tipo'] ?? 'text',
      options: (json['options'] as List? ?? [])
          .map((o) => OptionModel.fromJson(o))
          .toList(),
      answer: json['answer'],
      isRequired: json['is_required'] ?? false,
      dependsOnField: json['depends_on_field'],
      dependsOnValue: json['depends_on_value'],
      section: json['section'],
      hint: json['hint'],
      geometryType: json['geometry_type'],
      allowGpsOnly: json['allow_gps_only'] ?? false,
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      regexPattern: json['regex'],
      isPersistent: json['is_persistent'] == true || json['is_persistent'] == 1 || json['is_persistent'] == 'true',
      conditionOperator: json['condition_operator']?.toString() ?? '=',
    );
  }

  factory QuestionModel.fromSurveyQuestionModel(SurveyQuestionModel q) {
    List<OptionModel> parsedOptions = [];
    if (q.jOpciones != null) {
      dynamic rawList;
      if (q.jOpciones!['opciones'] is List) {
        rawList = q.jOpciones!['opciones'];
      } else if (q.jOpciones!['choices'] is List) {
        rawList = q.jOpciones!['choices'];
      } else if (q.jOpciones!['items'] is List) {
        rawList = q.jOpciones!['items'];
      } else if (q.jOpciones!['values'] is List) {
        rawList = q.jOpciones!['values'];
      }

      if (rawList is List) {
        parsedOptions = rawList.asMap().entries.map((e) {
          if (e.value is Map) {
            final valMap = e.value as Map;
            final label = valMap['label'] ?? valMap['text'] ?? valMap['name'] ?? valMap['value'] ?? e.value.toString();
            final val = valMap['value'] ?? valMap['name'] ?? label;
            return OptionModel(
              id: valMap['id'] ?? e.key,
              text: label.toString(),
              value: val.toString(),
            );
          } else {
            return OptionModel(
              id: e.key,
              text: e.value.toString(),
              value: e.value.toString(),
            );
          }
        }).toList();
      }
    }

    return QuestionModel(
      id: q.id,
      field: q.cCampo,
      text: q.cPregunta,
      type: q.cTipo,
      options: parsedOptions,
      isRequired: q.isRequired,
      dependsOnField: q.dependsOnField,
      dependsOnValue: q.dependsOnValue,
      section: q.section,
      hint: q.hint,
      geometryType: q.geometryType,
      allowGpsOnly: q.allowGpsOnly,
      minValue: q.minValue,
      maxValue: q.maxValue,
      regexPattern: q.regexPattern,
      isPersistent: q.isPersistent,
      conditionOperator: q.conditionOperator,
    );
  }
}

class OptionModel {
  final dynamic id;
  final String text;
  final String? value;

  OptionModel({
    required this.id,
    required this.text,
    this.value,
  });

  factory OptionModel.fromJson(Map<String, dynamic> json) {
    return OptionModel(
      id: json['id'] ?? 0,
      text: json['text'] ?? json['label'] ?? json['value']?.toString() ?? '',
      value: json['value']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'value': value,
    };
  }
}