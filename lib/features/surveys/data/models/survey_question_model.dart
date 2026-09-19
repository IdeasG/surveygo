import 'dart:convert';

class SurveyQuestionModel {
  final int id;
  final int idEncuesta;
  final String cCampo;
  final String cPregunta;
  final String cTipo;
  final Map<String, dynamic>? jOpciones;

  // Atributos extendidos para capacidades tipo KoBoToolbox / GIS
  final bool isRequired;
  final String? dependsOnField;
  final dynamic dependsOnValue;
  final String? section;
  final String? hint;
  final String? geometryType; // 'POINT', 'LINESTRING', 'POLYGON', 'ANY'
  final bool allowGpsOnly;
  final double? minValue;
  final double? maxValue;
  final String? regexPattern;
  final bool isPersistent;
  final String? conditionOperator; // '=', '!=', '>', '<', '>=', '<=', 'contains'

  SurveyQuestionModel({
    required this.id,
    required this.idEncuesta,
    required this.cCampo,
    required this.cPregunta,
    required this.cTipo,
    this.jOpciones,
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

  factory SurveyQuestionModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? opts;
    final rawOptions = json['j_opciones'] ?? json['options'];
    if (rawOptions != null) {
      if (rawOptions is String) {
        try {
          final decoded = jsonDecode(rawOptions);
          if (decoded is List) {
            opts = {'opciones': decoded};
          } else if (decoded is Map) {
            opts = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      } else if (rawOptions is List) {
        opts = {'opciones': rawOptions};
      } else if (rawOptions is Map) {
        opts = Map<String, dynamic>.from(rawOptions);
      }
    }

    // Extraer propiedades extendidas desde la raíz o desde j_opciones
    final requiredVal = json['is_required'] ?? opts?['is_required'] ?? false;
    final depField = json['depends_on_field'] ?? opts?['depends_on_field'];
    final depVal = json['depends_on_value'] ?? opts?['depends_on_value'];
    final sec = json['section'] ?? opts?['section'] ?? opts?['category'];
    final h = json['hint'] ?? opts?['hint'] ?? opts?['placeholder'];
    final geomType = json['geometry_type'] ?? opts?['geometry_type'];
    final gpsOnly = json['allow_gps_only'] ?? opts?['allow_gps_only'] ?? false;
    final minV = (json['min_value'] ?? opts?['min_value'])?.toDouble();
    final maxV = (json['max_value'] ?? opts?['max_value'])?.toDouble();
    final regex = json['regex'] ?? opts?['regex'];
    final persistentVal = json['is_persistent'] ?? opts?['is_persistent'] ?? false;
    final condOp = json['condition_operator'] ?? opts?['condition_operator'] ?? '=';

    int parsedId = 0;
    if (json['id'] is int) {
      parsedId = json['id'];
    } else if (json['id'] != null) {
      parsedId = int.tryParse(json['id'].toString()) ?? (json['id'].toString().hashCode.abs() % 2147483647);
    }

    int parsedSurveyId = 0;
    final rawSurveyId = json['id_encuesta'] ?? json['survey_id'];
    if (rawSurveyId is int) {
      parsedSurveyId = rawSurveyId;
    } else if (rawSurveyId != null) {
      parsedSurveyId = int.tryParse(rawSurveyId.toString()) ?? (rawSurveyId.toString().hashCode.abs() % 2147483647);
    }

    return SurveyQuestionModel(
      id: parsedId,
      idEncuesta: parsedSurveyId,
      cCampo: json['c_campo']?.toString() ?? json['field_name']?.toString() ?? '',
      cPregunta: json['c_pregunta']?.toString() ?? json['question_text']?.toString() ?? '',
      cTipo: (json['c_tipo'] ?? json['question_type'] ?? 'TEXT').toString().toUpperCase(),
      jOpciones: opts,
      isRequired: requiredVal == true || requiredVal == 1 || requiredVal == 'true',
      dependsOnField: depField?.toString(),
      dependsOnValue: depVal,
      section: sec?.toString(),
      hint: h?.toString(),
      geometryType: geomType?.toString(),
      allowGpsOnly: gpsOnly == true || gpsOnly == 1 || gpsOnly == 'true',
      minValue: minV,
      maxValue: maxV,
      regexPattern: regex?.toString(),
      isPersistent: persistentVal == true || persistentVal == 1 || persistentVal == 'true',
      conditionOperator: condOp?.toString(),
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
      'is_required': isRequired,
      'depends_on_field': dependsOnField,
      'depends_on_value': dependsOnValue,
      'section': section,
      'hint': hint,
      'geometry_type': geometryType,
      'allow_gps_only': allowGpsOnly,
      'min_value': minValue,
      'max_value': maxValue,
      'regex': regexPattern,
      'is_persistent': isPersistent,
      'condition_operator': conditionOperator,
    };
  }

  Map<String, dynamic> toMap() {
    // Empaquetar atributos extendidos en j_opciones si no estaban presentes
    final Map<String, dynamic> mergedOptions = Map<String, dynamic>.from(jOpciones ?? {});
    if (isRequired) mergedOptions['is_required'] = true;
    if (dependsOnField != null) mergedOptions['depends_on_field'] = dependsOnField;
    if (dependsOnValue != null) mergedOptions['depends_on_value'] = dependsOnValue;
    if (section != null) mergedOptions['section'] = section;
    if (hint != null) mergedOptions['hint'] = hint;
    if (geometryType != null) mergedOptions['geometry_type'] = geometryType;
    if (allowGpsOnly) mergedOptions['allow_gps_only'] = true;
    if (minValue != null) mergedOptions['min_value'] = minValue;
    if (maxValue != null) mergedOptions['max_value'] = maxValue;
    if (regexPattern != null) mergedOptions['regex'] = regexPattern;
    if (isPersistent) mergedOptions['is_persistent'] = true;
    if (conditionOperator != null) mergedOptions['condition_operator'] = conditionOperator;

    return {
      'id': id,
      'id_encuesta': idEncuesta,
      'c_campo': cCampo,
      'c_pregunta': cPregunta,
      'c_tipo': cTipo,
      'j_opciones': mergedOptions.isNotEmpty ? jsonEncode(mergedOptions) : null,
    };
  }

  static SurveyQuestionModel fromMap(Map<String, dynamic> map) {
    return SurveyQuestionModel.fromJson(map);
  }
}