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
  });

  factory SurveyQuestionModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? opts;
    if (json['j_opciones'] != null) {
      if (json['j_opciones'] is String) {
        try {
          final decoded = jsonDecode(json['j_opciones']);
          if (decoded is List) {
            opts = {'opciones': decoded};
          } else if (decoded is Map) {
            opts = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      } else if (json['j_opciones'] is List) {
        opts = {'opciones': json['j_opciones']};
      } else if (json['j_opciones'] is Map) {
        opts = Map<String, dynamic>.from(json['j_opciones']);
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

    return SurveyQuestionModel(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      idEncuesta: json['id_encuesta'] is int
          ? json['id_encuesta']
          : (int.tryParse(json['id_encuesta']?.toString() ?? '0') ?? 0),
      cCampo: json['c_campo']?.toString() ?? '',
      cPregunta: json['c_pregunta']?.toString() ?? '',
      cTipo: json['c_tipo']?.toString() ?? '',
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