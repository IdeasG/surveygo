import 'package:surveygo/features/surveys/data/models/survey_model.dart';

class HistoryModel {
  final int id;
  final SurveyModel survey;
  final DateTime completedDate;
  final String status; // 'completed', 'pending', 'error'
  final List<Map<String, dynamic>> responses; // Almacena las respuestas
  final String responseSetId; // Identificador del conjunto de respuestas

  HistoryModel({
    required this.id,
    required this.survey,
    required this.completedDate,
    required this.status,
    this.responses = const [],
    this.responseSetId = 'default',
  });

  factory HistoryModel.fromJson(Map<String, dynamic> json) {
    return HistoryModel(
      id: json['id'] ?? 0,
      survey: SurveyModel.fromJson(json['survey'] ?? {}),
      completedDate: DateTime.parse(json['completed_date'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'pending',
      responses: (json['responses'] as List? ?? []).cast<Map<String, dynamic>>(),
      responseSetId: json['response_set_id'] ?? 'default',
    );
  }
}